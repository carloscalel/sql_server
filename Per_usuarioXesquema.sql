-- CTE: Usuarios y sus roles
WITH UserRoles AS (
    SELECT 
        m.member_principal_id AS user_principal_id,
        r.name AS role_name,
        r.principal_id AS role_principal_id
    FROM 
        sys.database_role_members m
    JOIN 
        sys.database_principals r ON m.role_principal_id = r.principal_id
),
-- CTE: Permisos explícitos
ExplicitPerms AS (
    SELECT
        dp.principal_id,
        dp.name AS Grantee,
        dp.type_desc AS Tipo,
        perm.class_desc,
        s.name AS Esquema,
        OBJECT_NAME(perm.major_id) AS Objeto,
        perm.permission_name AS Permiso,
        perm.state_desc AS Estado
    FROM
        sys.database_permissions perm
    LEFT JOIN sys.schemas s ON perm.class_desc = 'SCHEMA' AND perm.major_id = s.schema_id
    JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
),
-- CTE: Permisos heredados por roles
InheritedPerms AS (
    SELECT
        ur.user_principal_id,
        dp.name AS Grantee,
        dp.type_desc AS Tipo,
        perm.class_desc,
        s.name AS Esquema,
        OBJECT_NAME(perm.major_id) AS Objeto,
        perm.permission_name AS Permiso,
        perm.state_desc AS Estado,
        ur.role_name AS A_traves_del_Rol
    FROM 
        UserRoles ur
    JOIN sys.database_permissions perm ON perm.grantee_principal_id = ur.role_principal_id
    JOIN sys.database_principals dp ON ur.user_principal_id = dp.principal_id
    LEFT JOIN sys.schemas s ON perm.class_desc = 'SCHEMA' AND perm.major_id = s.schema_id
)

-- UNION: Mostrar permisos directos e indirectos
SELECT 
    Grantee,
    Tipo,
    class_desc AS Tipo_Objeto,
    ISNULL(Esquema, '-') AS Esquema,
    ISNULL(Objeto, '-') AS Objeto,
    Permiso,
    Estado,
    NULL AS A_traves_del_Rol
FROM ExplicitPerms

UNION

SELECT 
    Grantee,
    Tipo,
    class_desc AS Tipo_Objeto,
    ISNULL(Esquema, '-') AS Esquema,
    ISNULL(Objeto, '-') AS Objeto,
    Permiso,
    Estado,
    A_traves_del_Rol
FROM InheritedPerms

ORDER BY 
    Grantee, Esquema, Objeto, Permiso;
