SELECT
    dp.name AS Usuario,
    dp.type_desc AS Tipo,
    perm.permission_name AS Permiso,
    perm.state_desc AS Estado,
    s.name AS Esquema
FROM
    sys.database_permissions AS perm
JOIN
    sys.schemas AS s ON perm.major_id = s.schema_id
JOIN
    sys.database_principals AS dp ON perm.grantee_principal_id = dp.principal_id
WHERE
    perm.class = 3  -- Clase 3 = Schema
ORDER BY
    s.name, dp.name, perm.permission_name;
