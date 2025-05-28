SELECT * 
FROM OPENQUERY(MiLinkedServer, '
-- Consulta para obtener información de usuarios de SQL Server

-- Información de usuarios a nivel de servidor
SELECT 
    ''Servidor'' AS Alcance,
    sp.name AS NombreUsuario,
    sp.type_desc AS TipoPrincipal,
    sp.default_database_name AS BaseDatosPredeterminada,
    sp.create_date AS FechaCreacion,
    sp.modify_date AS FechaModificacion,
    ISNULL(perm.class_desc, '''') AS ClasePermiso,
    ISNULL(perm.permission_name, '''') AS Permiso,
    ISNULL(perm.state_desc, '''') AS EstadoPermiso,
    ISNULL(CAST(perm.major_id AS NVARCHAR), '''') AS IdObjeto,
    ISNULL(roles.RolePath, '''') AS RolesAsignados,
    MAX(ses.login_time) AS UltimaConexion,
    MAX(CONVERT(VARCHAR(100), ses.login_time, 120)) AS UltimaConexionExacta,
    MAX(con.client_net_address) AS UltimaIP,
    MAX(ses.host_name) AS UltimoHostCliente,
    MAX(ses.program_name) AS UltimaAplicacionCliente,
    @@SERVERNAME AS Servidor,
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
                FOR XML PATH(''''), TYPE).value('.', 'NVARCHAR(MAX)')
           , 1, 2, '') AS RolePath
    FROM sys.server_role_members srm1
    GROUP BY member_principal_id
) roles ON sp.principal_id = roles.member_principal_id
WHERE sp.type IN (''S'', ''U'', ''G'')
GROUP BY sp.name, sp.type_desc, sp.default_database_name, sp.create_date, sp.modify_date,
         perm.class_desc, perm.permission_name, perm.state_desc, perm.major_id, roles.RolePath, sp.sid, sl.is_policy_checked, sl.is_expiration_checked

UNION ALL

-- Información de usuarios a nivel de base de datos
SELECT 
    ''Base de Datos'' AS Alcance,
    dp.name AS NombreUsuario,
    dp.type_desc AS TipoPrincipal,
    NULL AS BaseDatosPredeterminada,
    dp.create_date AS FechaCreacion,
    dp.modify_date AS FechaModificacion,
    ISNULL(perm.class_desc, '''') AS ClasePermiso,
    ISNULL(perm.permission_name, '''') AS Permiso,
    ISNULL(perm.state_desc, '''') AS EstadoPermiso,
    ISNULL(CAST(perm.major_id AS NVARCHAR), '''') AS IdObjeto,
    ISNULL(roles.RolePath, '''') AS RolesAsignados,
    NULL AS UltimaConexion,
    NULL AS UltimaConexionExacta,
    NULL AS UltimaIP,
    NULL AS UltimoHostCliente,
    NULL AS UltimaAplicacionCliente,
    @@SERVERNAME AS Servidor,
    DB_NAME() AS BaseDatos,
    NULL AS DiasSinConexion,
    NULL AS PoliticaContraseña,
    NULL AS CaducidadContraseña
FROM sys.database_principals dp
LEFT JOIN sys.database_permissions perm ON dp.principal_id = perm.grantee_principal_id
LEFT JOIN (
    SELECT member_principal_id,
           STUFF((
                SELECT '', '' + drp2.name
                FROM sys.database_role_members drm2
                JOIN sys.database_principals drp2 ON drm2.role_principal_id = drp2.principal_id
                WHERE drm2.member_principal_id = drm1.member_principal_id
                FOR XML PATH(''''), TYPE).value('.', 'NVARCHAR(MAX)')
           , 1, 2, '') AS RolePath
    FROM sys.database_role_members drm1
    GROUP BY member_principal_id
) roles ON dp.principal_id = roles.member_principal_id
WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'')
');
