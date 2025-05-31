
DECLARE @ServerCollation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));

DECLARE @DBName NVARCHAR(255);
DECLARE @DBCursor CURSOR;

SET @DBCursor = CURSOR FOR 
SELECT name FROM sys.databases WHERE database_id > 4;

OPEN @DBCursor;
FETCH NEXT FROM @DBCursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC(
    'SELECT 
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
        ''' + @DBName + ''' AS BaseDatos,
        NULL AS DiasSinConexion,
        NULL AS PoliticaContraseña,
        NULL AS CaducidadContraseña
    FROM [' + @DBName + '].sys.database_principals dp
    LEFT JOIN [' + @DBName + '].sys.database_permissions perm ON dp.principal_id = perm.grantee_principal_id
    LEFT JOIN (
        SELECT member_principal_id,
               STUFF((
                    SELECT '', '' + drp2.name
                    FROM [' + @DBName + '].sys.database_role_members drm2
                    JOIN [' + @DBName + '].sys.database_principals drp2 ON drm2.role_principal_id = drp2.principal_id
                    WHERE drm2.member_principal_id = drm1.member_principal_id
                    FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)'')
               , 1, 2, '''') AS RolePath
        FROM [' + @DBName + '].sys.database_role_members drm1
        GROUP BY drm1.member_principal_id
    ) roles ON dp.principal_id = roles.member_principal_id
    WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'')'
    );
    FETCH NEXT FROM @DBCursor INTO @DBName;
END;

CLOSE @DBCursor;
DEALLOCATE @DBCursor;
