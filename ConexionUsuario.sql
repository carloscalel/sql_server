-- ============================================
-- Consulta Unificada: Logins + Usuarios
-- ============================================

-- CTE para jerarquía de roles a nivel de instancia
WITH ServerRoleHierarchy AS (
    SELECT 
        member_principal_id,
        role_principal_id,
        CAST(sp_role.name AS NVARCHAR(MAX)) AS RolePath
    FROM sys.server_role_members srm
    JOIN sys.server_principals sp_role ON srm.role_principal_id = sp_role.principal_id

    UNION ALL

    SELECT 
        srm.member_principal_id,
        srm.role_principal_id,
        CAST(srh.RolePath + ' > ' + sp_role.name AS NVARCHAR(MAX)) AS RolePath
    FROM sys.server_role_members srm
    JOIN sys.server_principals sp_role ON srm.role_principal_id = sp_role.principal_id
    JOIN ServerRoleHierarchy srh ON srm.member_principal_id = srh.role_principal_id
)
-- Consulta unificada
SELECT 
    'Server' AS Scope,
    sp.name AS PrincipalName,
    sp.type_desc AS PrincipalType,
    sp.default_database_name AS DefaultDB,
    sp.create_date,
    sp.modify_date,
    ISNULL(perm.class_desc, '') AS ClassDesc,
    ISNULL(perm.permission_name, '') AS Permission,
    ISNULL(perm.state_desc, '') AS PermissionState,
    ISNULL(perm.major_id, 0) AS MajorID,
    ISNULL(roles.RolePath, '') AS Roles,
    MAX(ses.login_time) AS LastLoginTime,
    NULL AS DatabaseName
FROM sys.server_principals sp
LEFT JOIN sys.dm_exec_sessions ses
    ON sp.sid = ses.security_id
LEFT JOIN sys.server_permissions perm
    ON sp.principal_id = perm.grantee_principal_id
LEFT JOIN (
    SELECT 
        member_principal_id,
        STUFF((
            SELECT ', ' + RolePath
            FROM ServerRoleHierarchy sr2
            WHERE sr2.member_principal_id = sr1.member_principal_id
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS RolePath
    FROM ServerRoleHierarchy sr1
    GROUP BY member_principal_id
) roles ON sp.principal_id = roles.member_principal_id
WHERE sp.type IN ('S', 'U', 'G')
GROUP BY 
    sp.name, sp.type_desc, sp.default_database_name, sp.create_date, sp.modify_date,
    perm.class_desc, perm.permission_name, perm.state_desc, perm.major_id, roles.RolePath

UNION ALL

-- Consulta dinámica para cada base de datos
DECLARE @DBName NVARCHAR(255);
DECLARE @DynamicSQL NVARCHAR(MAX) = '';

DECLARE db_cursor CURSOR FOR 
SELECT name FROM sys.databases WHERE database_id > 4; -- Omitir bases de sistema

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @DynamicSQL += '
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
    LEFT JOIN [' + @DBName + '].sys.database_permissions perm
        ON dp.principal_id = perm.grantee_principal_id
    LEFT JOIN (
        WITH DBRoleHierarchy AS (
            SELECT 
                drm.member_principal_id,
                drm.role_principal_id,
                CAST(drp_role.name AS NVARCHAR(MAX)) AS RolePath
            FROM [' + @DBName + '].sys.database_role_members drm
            JOIN [' + @DBName + '].sys.database_principals drp_role ON drm.role_principal_id = drp_role.principal_id
            UNION ALL
            SELECT 
                drm.member_principal_id,
                drm.role_principal_id,
                CAST(drh.RolePath + '' > '' + drp_role.name AS NVARCHAR(MAX)) AS RolePath
            FROM [' + @DBName + '].sys.database_role_members drm
            JOIN [' + @DBName + '].sys.database_principals drp_role ON drm.role_principal_id = drp_role.principal_id
            JOIN DBRoleHierarchy drh ON drm.member_principal_id = drh.role_principal_id
        )
        SELECT 
            member_principal_id,
            STUFF((
                SELECT '', '' + RolePath
                FROM DBRoleHierarchy dr2
                WHERE dr2.member_principal_id = dr1.member_principal_id
                FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)''), 1, 2, '''') AS RolePath
        FROM DBRoleHierarchy dr1
        GROUP BY member_principal_id
    ) roles ON dp.principal_id = roles.member_principal_id
    WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'') 
    ';
    FETCH NEXT FROM db_cursor INTO @DBName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Ejecutar consulta dinámica
EXEC sp_executesql @DynamicSQL;
