-- Reemplaza 'TuBaseDeDatos' con el nombre de tu base de datos
USE TuBaseDeDatos;
GO

-- Reemplaza 'TuEsquema' con el nombre del esquema que deseas inspeccionar
DECLARE @SchemaName SYSNAME = 'TuEsquema';

SELECT
    prin.name AS PrincipalName,
    CASE
        WHEN prin.type_desc = 'SQL_USER' THEN 'Usuario SQL'
        WHEN prin.type_desc = 'WINDOWS_USER' THEN 'Usuario Windows'
        WHEN prin.type_desc = 'DATABASE_ROLE' THEN 'Rol de Base de Datos'
        WHEN prin.type_desc = 'SERVER_ROLE' THEN 'Rol de Servidor'
        ELSE prin.type_desc
    END AS PrincipalType,
    perm.permission_name AS PermissionName,
    perm.state_desc AS PermissionState
FROM
    sys.database_permissions perm
INNER JOIN
    sys.database_principals prin ON perm.grantee_principal_id = prin.principal_id
INNER JOIN
    sys.schemas sch ON perm.major_id = sch.schema_id
WHERE
    sch.name = @SchemaName
ORDER BY
    prin.name, perm.permission_name;
GO
