-- ============================================
-- A NIVEL DE INSTANCIA (Logins, permisos, roles anidados y última conexión)
-- ============================================

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
-- Combina los permisos y la jerarquía de roles
SELECT 
    sp.name AS LoginName,
    sp.type_desc AS LoginType,
    sp.default_database_name AS DefaultDB,
    sp.create_date,
    sp.modify_date,
    ISNULL(perm.class_desc, '') AS ClassDesc,
    ISNULL(perm.permission_name, '') AS Permission,
    ISNULL(perm.state_desc, '') AS PermissionState,
    ISNULL(perm.major_id, 0) AS MajorID,
    ISNULL(roles.RolePath, '') AS ServerRoles,
    MAX(ses.login_time) AS LastLoginTime
FROM sys.server_principals sp
LEFT JOIN sys.dm_exec_sessions ses
    ON sp.sid = ses.security_id
LEFT JOIN (
    SELECT 
        grantee_principal_id,
        class_desc,
        permission_name,
        state_desc,
        major_id
    FROM sys.server_permissions
) perm ON sp.principal_id = perm.grantee_principal_id
LEFT JOIN (
    SELECT 
        member_principal_id,
        STRING_AGG(RolePath, ', ') AS RolePath
    FROM ServerRoleHierarchy
    GROUP BY member_principal_id
) roles ON sp.principal_id = roles.member_principal_id
WHERE sp.type IN ('S', 'U', 'G')
GROUP BY 
    sp.name, sp.type_desc, sp.default_database_name, sp.create_date, sp.modify_date,
    perm.class_desc, perm.permission_name, perm.state_desc, perm.major_id, roles.RolePath
ORDER BY sp.name;

-- ============================================
-- A NIVEL DE BASE DE DATOS (Usuarios, permisos, roles anidados)
-- ============================================

DECLARE @DBName NVARCHAR(255);

DECLARE db_cursor CURSOR FOR 
SELECT name 
FROM sys.databases
WHERE database_id > 4 -- Omitir bases de sistema (opcional)

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Base de datos: ' + @DBName;
    DECLARE @SQL NVARCHAR(MAX);

    SET @SQL = '
    USE [' + @DBName + '];

    WITH DBRoleHierarchy AS (
        SELECT 
            drm.member_principal_id,
            drm.role_principal_id,
            CAST(drp_role.name AS NVARCHAR(MAX)) AS RolePath
        FROM sys.database_role_members drm
        JOIN sys.database_principals drp_role ON drm.role_principal_id = drp_role.principal_id

        UNION ALL

        SELECT 
            drm.member_principal_id,
            drm.role_principal_id,
            CAST(drh.RolePath + '' > '' + drp_role.name AS NVARCHAR(MAX)) AS RolePath
        FROM sys.database_role_members drm
        JOIN sys.database_principals drp_role ON drm.role_principal_id = drp_role.principal_id
        JOIN DBRoleHierarchy drh ON drm.member_principal_id = drh.role_principal_id
    )
    SELECT 
        dp.name AS UserName,
        dp.type_desc AS UserType,
        dp.create_date,
        dp.modify_date,
        ISNULL(perm.class_desc, '''') AS ClassDesc,
        ISNULL(perm.permission_name, '''') AS Permission,
        ISNULL(perm.state_desc, '''') AS PermissionState,
        ISNULL(perm.major_id, 0) AS MajorID,
        ISNULL(roles.RolePath, '''') AS DatabaseRoles
    FROM sys.database_principals dp
    LEFT JOIN (
        SELECT 
            grantee_principal_id,
            class_desc,
            permission_name,
            state_desc,
            major_id
        FROM sys.database_permissions
    ) perm ON dp.principal_id = perm.grantee_principal_id
    LEFT JOIN (
        SELECT 
            member_principal_id,
            STRING_AGG(RolePath, '', '') AS RolePath
        FROM DBRoleHierarchy
        GROUP BY member_principal_id
    ) roles ON dp.principal_id = roles.member_principal_id
    WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'')
    ORDER BY dp.name;
    ';

    EXEC sp_executesql @SQL;
    FETCH NEXT FROM db_cursor INTO @DBName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
