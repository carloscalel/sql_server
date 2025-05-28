DECLARE @SQL NVARCHAR(MAX) = '';

DECLARE @ServerCollation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));

SET @SQL += '
SELECT 
    ''Server'' AS Scope,
    sp.name COLLATE ' + @ServerCollation + ' AS PrincipalName,
    sp.type_desc COLLATE ' + @ServerCollation + ' AS PrincipalType,
    sp.default_database_name COLLATE ' + @ServerCollation + ' AS DefaultDB,
    sp.create_date,
    sp.modify_date,
    ISNULL(perm.class_desc COLLATE ' + @ServerCollation + ', '''') AS ClassDesc,
    ISNULL(perm.permission_name COLLATE ' + @ServerCollation + ', '''') AS Permission,
    ISNULL(perm.state_desc COLLATE ' + @ServerCollation + ', '''') AS PermissionState,
    ISNULL(CAST(perm.major_id AS NVARCHAR) COLLATE ' + @ServerCollation + ', '''') AS MajorID,
    ISNULL(roles.RolePath COLLATE ' + @ServerCollation + ', '''') AS Roles,
    MAX(ses.login_time) AS LastLoginTime,
    MAX(con.client_net_address) AS LastClientIP,
    MAX(ses.host_name) AS LastClientHost,
    ''' + @ServerName + ''' AS ServerName,
    NULL AS DatabaseName
FROM sys.server_principals sp
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
         perm.class_desc, perm.permission_name, perm.state_desc, perm.major_id, roles.RolePath, sp.sid
';

-- ============================================
-- Parte 2: Usuarios en bases de datos
-- ============================================
DECLARE @DBName NVARCHAR(255);
DECLARE @DBCursor CURSOR;

SET @DBCursor = CURSOR FOR 
SELECT name FROM sys.databases WHERE database_id > 4;

OPEN @DBCursor;
FETCH NEXT FROM @DBCursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL += '
    UNION ALL
    SELECT 
        ''Database'' AS Scope,
        dp.name COLLATE ' + @ServerCollation + ' AS PrincipalName,
        dp.type_desc COLLATE ' + @ServerCollation + ' AS PrincipalType,
        NULL AS DefaultDB,
        dp.create_date,
        dp.modify_date,
        ISNULL(perm.class_desc COLLATE ' + @ServerCollation + ', '''') AS ClassDesc,
        ISNULL(perm.permission_name COLLATE ' + @ServerCollation + ', '''') AS Permission,
        ISNULL(perm.state_desc COLLATE ' + @ServerCollation + ', '''') AS PermissionState,
        ISNULL(CAST(perm.major_id AS NVARCHAR) COLLATE ' + @ServerCollation + ', '''') AS MajorID,
        ISNULL(roles.RolePath COLLATE ' + @ServerCollation + ', '''') AS Roles,
        NULL AS LastLoginTime,
        NULL AS LastClientIP,
        NULL AS LastClientHost,
        ''' + @ServerName + ''' AS ServerName,
        ''' + @DBName + ''' AS DatabaseName
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
    WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'')
    ';
    FETCH NEXT FROM @DBCursor INTO @DBName;
END;

CLOSE @DBCursor;
DEALLOCATE @DBCursor;

-- ============================================
-- Ejecutar consulta final
-- ============================================
EXEC sp_executesql @SQL;
