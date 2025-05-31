-- Elimina la tabla temporal global si existe
IF OBJECT_ID('tempdb..#Resultados') IS NOT NULL
    DROP TABLE #Resultados;

-- Crea la tabla temporal global con la estructura del SELECT
CREATE TABLE #Resultados (
    Alcance NVARCHAR(50),
    NombreUsuario NVARCHAR(256),
    TipoPrincipal NVARCHAR(256),
    BaseDatosPredeterminada NVARCHAR(256),
    FechaCreacion DATETIME,
    FechaModificacion DATETIME,
    ClasePermiso NVARCHAR(256),
    Permiso NVARCHAR(256),
    EstadoPermiso NVARCHAR(256),
    IdObjeto NVARCHAR(256),
    RolesAsignados NVARCHAR(MAX),
    UltimaConexion NVARCHAR(256),
    UltimaConexionExacta NVARCHAR(256),
    UltimaIP NVARCHAR(256),
    UltimoHostCliente NVARCHAR(256),
    UltimaAplicacionCliente NVARCHAR(256),
    Servidor NVARCHAR(256),
    BaseDatos NVARCHAR(256),
    DiasSinConexion NVARCHAR(256),
    PoliticaContraseña NVARCHAR(256),
    CaducidadContraseña NVARCHAR(256)
);

DECLARE @InnerCommand NVARCHAR(MAX);

SET @InnerCommand = N'
SET QUOTED_IDENTIFIER ON; -- Corregimos el error
USE [?];
SELECT 
    ''Database'' AS Alcance,
    dp.name COLLATE Modern_Spanish_CI_AS AS NombreUsuario,
    dp.type_desc COLLATE Modern_Spanish_CI_AS AS TipoPrincipal,
    NULL AS BaseDatosPredeterminada,
    dp.create_date AS FechaCreacion,
    dp.modify_date AS FechaModificacion,
    ISNULL(perm.class_desc COLLATE Modern_Spanish_CI_AS, '''') AS ClasePermiso,
    ISNULL(perm.permission_name COLLATE Modern_Spanish_CI_AS, '''') AS Permiso,
    ISNULL(perm.state_desc COLLATE Modern_Spanish_CI_AS, '''') AS EstadoPermiso,
    ISNULL(CAST(perm.major_id AS NVARCHAR) COLLATE Modern_Spanish_CI_AS, '''') AS IdObjeto,
    ISNULL(roles.RolePath COLLATE Modern_Spanish_CI_AS, '''') AS RolesAsignados,
    NULL AS UltimaConexion,
    NULL AS UltimaConexionExacta,
    NULL AS UltimaIP,
    NULL AS UltimoHostCliente,
    NULL AS UltimaAplicacionCliente,
    @@SERVERNAME AS Servidor,
    DB_NAME() AS BaseDatos,
    NULL AS DiasSinConexion,
    NULL AS PoliticaContraseña,
    NULL AS CaducidadContraseña
FROM sys.database_principals dp
LEFT JOIN sys.database_permissions perm ON dp.principal_id = perm.grantee_principal_id
LEFT JOIN (
    SELECT member_principal_id,
            STUFF((
                SELECT '', '' + drp2.name
                FROM sys.database_role_members drm2
                JOIN sys.database_principals drp2 ON drm2.role_principal_id = drp2.principal_id
                WHERE drm2.member_principal_id = drm1.member_principal_id
                FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)'')
            , 1, 2, '''') AS RolePath
    FROM sys.database_role_members drm1
    GROUP BY drm1.member_principal_id
) roles ON dp.principal_id = roles.member_principal_id
WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'')
'

-- Construimos la llamada completa a sp_MSforeachdb
DECLARE @FullCommand NVARCHAR(MAX)
SET @FullCommand = N'EXEC master.sys.sp_MSforeachdb @command1 = N''' + REPLACE(@InnerCommand, '''', '''''') + ''''

-- Ejecutamos el comando
INSERT INTO #Resultados
EXEC sp_executesql @FullCommand;

-- Finalmente, consulta los resultados
SELECT * FROM #Resultados WITH(NOLOCK);
