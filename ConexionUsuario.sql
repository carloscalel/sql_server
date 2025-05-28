DECLARE @SQL NVARCHAR(MAX) = '';

-- ============================================
-- Parte 1: Logins (a nivel de instancia)
-- ============================================
SET @SQL += '
SELECT 
    ''Server'' AS Scope,
    sp.name AS PrincipalName,
    sp.type_desc AS PrincipalType,
    sp.default_database_name AS DefaultDB,
    sp.create_date,
    sp.modify_date,
    ISNULL(perm.class_desc, '''') AS ClassDesc,
    ISNULL(perm.permission_name, '''') AS Permission,
    ISNULL(perm.state_desc, '''') AS PermissionState,
    ISNULL(perm.major_id, 0) AS MajorID,
    ISNULL(roles.RolePath, '''') AS Roles,
    MAX(ses.login_time) AS LastLoginTime,
    NULL AS DatabaseName
FROM sys.server_principals sp
LEFT JOIN sys.dm_exec_sessions ses ON sp.sid = ses.security_id
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
-- Parte 2: Usuarios en cada base de datos
-- ============================================
DECLARE @DBName NVARCHAR(255);
DECLARE @DBCursor CURSOR;

SET @DBCursor = CURSOR FOR 
SELECT name FROM sys.databases WHERE database_id > 4; -- Omitir bases de sistema

OPEN @DBCursor;
FETCH NEXT FROM @DBCursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL += '
    UNION ALL
    SELECT 
        ''Database'' AS Scope,
        dp.name AS PrincipalName,
        dp.type_desc AS PrincipalType,
        NULL AS DefaultDB,
        dp.create_date,
        dp.modify_date,
        ISNULL(perm.class_desc, '''') AS ClassDesc,
        ISNULL(perm.permission_name, '''') AS Permission,
        ISNULL(perm.state_desc, '''') AS PermissionState,
        ISNULL(perm.major_id, 0) AS MajorID,
        ISNULL(roles.RolePath, '''') AS Roles,
        NULL AS LastLoginTime,
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
-- Ejecutar consulta completa
-- ============================================
EXEC sp_executesql @SQL;
