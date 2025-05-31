DECLARE @ServerCollation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;  -- Cambiar por el nombre real del Linked Server

DECLARE @SQL NVARCHAR(MAX) = N'';

-- Construimos el SQL original, como lo hacías
SET @SQL += N'
SELECT 
    ''Server'' AS Alcance,
    sp.name COLLATE ' + @ServerCollation + N' AS NombreUsuario,
    sp.type_desc COLLATE ' + @ServerCollation + N' AS TipoPrincipal,
    sp.default_database_name COLLATE ' + @ServerCollation + N' AS BaseDatosPredeterminada,
    sp.create_date AS FechaCreacion,
    sp.modify_date AS FechaModificacion,
    ISNULL(perm.class_desc COLLATE ' + @ServerCollation + N', '''') AS ClasePermiso,
    ISNULL(perm.permission_name COLLATE ' + @ServerCollation + N', '''') AS Permiso,
    ISNULL(perm.state_desc COLLATE ' + @ServerCollation + N', '''') AS EstadoPermiso,
    ISNULL(CAST(perm.major_id AS NVARCHAR) COLLATE ' + @ServerCollation + N', '''') AS IdObjeto,
    ISNULL(roles.RolePath COLLATE ' + @ServerCollation + N', '''') AS RolesAsignados,
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
                FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)'')
           , 1, 2, '''') AS RolePath
    FROM sys.server_role_members srm1
    GROUP BY member_principal_id
) roles ON sp.principal_id = roles.member_principal_id
WHERE sp.type IN (''S'', ''U'', ''G'')
GROUP BY sp.name, sp.type_desc, sp.default_database_name, sp.create_date, sp.modify_date,
         perm.class_desc, perm.permission_name, perm.state_desc, perm.major_id, roles.RolePath, sp.sid, sl.is_policy_checked, sl.is_expiration_checked
';

-- Muy importante: escapamos las comillas simples duplicándolas
SET @SQL = REPLACE(@SQL, '''', '''''');

-- Construimos el OPENQUERY con el SQL escapado y encerrado entre comillas simples
DECLARE @OpenQuery NVARCHAR(MAX);
SET @OpenQuery = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@ServerName) + N', ''' + @SQL + N''')';

-- Ejecutamos el SQL dinámico
--PRINT @OpenQuery
EXEC (@OpenQuery);

