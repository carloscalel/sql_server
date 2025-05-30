DECLARE @SQL NVARCHAR(MAX) = '';

DECLARE @ServerCollation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));

-- Parte 1: Usuarios a nivel de servidor
SET @SQL += '
SELECT 
    ''Server'' AS Alcance,
    sp.name COLLATE ' + @ServerCollation + ' AS NombreUsuario,
    sp.type_desc COLLATE ' + @ServerCollation + ' AS TipoPrincipal,
    sp.default_database_name COLLATE ' + @ServerCollation + ' AS BaseDatosPredeterminada,
    sp.create_date AS FechaCreacion,
    sp.modify_date AS FechaModificacion,
    ISNULL(perm.class_desc COLLATE ' + @ServerCollation + ', '''') AS ClasePermiso,
    ISNULL(perm.permission_name COLLATE ' + @ServerCollation + ', '''') AS Permiso,
    ISNULL(perm.state_desc COLLATE ' + @ServerCollation + ', '''') AS EstadoPermiso,
    ISNULL(CAST(perm.major_id AS NVARCHAR) COLLATE ' + @ServerCollation + ', '''') AS IdObjeto,
    ISNULL(roles.RolePath COLLATE ' + @ServerCollation + ', '''') AS RolesAsignados,
    MAX(ses.login_time) AS UltimaConexion,
    MAX(CONVERT(VARCHAR(100), ses.login_time, 120)) AS UltimaConexionExacta,
    MAX(con.client_net_address) AS UltimaIP,
    MAX(ses.host_name) AS UltimoHostCliente,
    MAX(ses.program_name) AS UltimaAplicacionCliente,
    ''' + @ServerName + ''' AS Servidor,
    NULL AS BaseDatos,
    DATEDIFF(DAY, MAX(ses.login_time), GETDATE()) AS DiasSinConexion,
    CASE WHEN sl.is_policy_checked = 1 THEN ''Sí'' ELSE ''No'' END AS PoliticaContraseña,
    CASE WHEN sl.is_expiration_checked = 1 THEN ''Sí'' ELSE ''No'' END AS CaducidadContraseña
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sp.principal_id = sl.principal_id
LEFT JOIN sys.dm_exec_sessions ses ON sp.sid = ses.security_id
LEFT JOIN sys.dm_exec_connections con ON ses.session_id = con.session_id
LEFT JOIN sys.server_permissions perm ON sp.principal_id = perm.grantee_principal_id
LEFT JOIN (
    SELECT member_principal_id,
           STUFF((
                SELECT '', '' + sp2.name
                FROM sys.server_role_members srm2
                JOIN sys.server_principals sp2 ON srm2.role_principal_id = sp2.principal_id
                WHERE srm2.member_principal_id = srm1.member_principal_id
                FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)'')
           , 1, 2, '''') AS RolePath
    FROM sys.server_role_members srm1
    GROUP BY member_principal_id
) roles ON sp.principal_id = roles.member_principal_id
WHERE sp.type IN (''S'', ''U'', ''G'')
GROUP BY sp.name, sp.type_desc, sp.default_database_name, sp.create_date, sp.modify_date,
         perm.class_desc, perm.permission_name, perm.state_desc, perm.major_id, roles.RolePath, sp.sid, sl.is_policy_checked, sl.is_expiration_checked
';

-- Crear tabla temporal para guardar resultados
IF OBJECT_ID('tempdb..#Resultados') IS NOT NULL DROP TABLE #Resultados;
CREATE TABLE #Resultados (
    Alcance NVARCHAR(50),
    NombreUsuario NVARCHAR(128),
    TipoPrincipal NVARCHAR(60),
    BaseDatosPredeterminada NVARCHAR(128),
    FechaCreacion DATETIME,
    FechaModificacion DATETIME,
    ClasePermiso NVARCHAR(128),
    Permiso NVARCHAR(128),
    EstadoPermiso NVARCHAR(60),
    IdObjeto NVARCHAR(128),
    RolesAsignados NVARCHAR(MAX),
    UltimaConexion DATETIME,
    UltimaConexionExacta NVARCHAR(100),
    UltimaIP NVARCHAR(48),
    UltimoHostCliente NVARCHAR(128),
    UltimaAplicacionCliente NVARCHAR(128),
    Servidor NVARCHAR(128),
    BaseDatos NVARCHAR(128),
    DiasSinConexion INT,
    PoliticaContraseña NVARCHAR(2),
    CaducidadContraseña NVARCHAR(2)
);

-- Insertar resultados del servidor
INSERT INTO #Resultados
EXEC sp_executesql @SQL;

-- Usar sp_MSforeachdb para recorrer las bases de datos excepto las del sistema
EXEC sp_MSforeachdb '
IF ''?'' NOT IN (''master'', ''model'', ''msdb'', ''tempdb'') 
BEGIN
    INSERT INTO #Resultados
    SELECT 
        ''Database'' AS Alcance,
        dp.name COLLATE ' + @ServerCollation + ' AS NombreUsuario,
        dp.type_desc COLLATE ' + @ServerCollation + ' AS TipoPrincipal,
        NULL AS BaseDatosPredeterminada,
        dp.create_date AS FechaCreacion,
        dp.modify_date AS FechaModificacion,
        ISNULL(perm.class_desc COLLATE ' + @ServerCollation + ', '''') AS ClasePermiso,
        ISNULL(perm.permission_name COLLATE ' + @ServerCollation + ', '''') AS Permiso,
        ISNULL(perm.state_desc COLLATE ' + @ServerCollation + ', '''') AS EstadoPermiso,
        ISNULL(CAST(perm.major_id AS NVARCHAR) COLLATE ' + @ServerCollation + ', '''') AS IdObjeto,
        ISNULL(roles.RolePath COLLATE ' + @ServerCollation + ', '''') AS RolesAsignados,
        NULL AS UltimaConexion,
        NULL AS UltimaConexionExacta,
        NULL AS UltimaIP,
        NULL AS UltimoHostCliente,
        NULL AS UltimaAplicacionCliente,
        ''' + @ServerName + ''' AS Servidor,
        ''?'' AS BaseDatos,
