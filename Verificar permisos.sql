SELECT 
    princ.name AS PrincipalName,
    perm.permission_name,
    perm.state_desc,
    perm.class_desc,
    obj.name AS ObjectName
FROM sys.database_permissions AS perm
JOIN sys.database_principals AS princ ON perm.grantee_principal_id = princ.principal_id
LEFT JOIN sys.objects AS obj ON perm.major_id = obj.object_id
WHERE perm.class_desc = 'SCHEMA'
AND SCHEMA_NAME(perm.major_id) = 'NombreDelEsquema';
