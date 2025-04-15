SELECT
    r.session_id AS [Session ID],
    r.blocking_session_id AS [Blocking Session ID],
    r.status AS [Request Status],
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    DB_NAME(r.database_id) AS [Database],
    OBJECT_NAME(p.object_id) AS [Table Name],
    r.command,
    t.text AS [SQL Text],
    s.login_name AS [Login Name],
    s.host_name,
    s.program_name,
    r.start_time,
    r.cpu_time,
    r.reads,
    r.writes
FROM sys.dm_exec_requests r
LEFT JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
LEFT JOIN sys.dm_exec_requests req ON req.blocking_session_id = r.session_id
LEFT JOIN sys.dm_exec_requests br ON r.blocking_session_id = br.session_id
LEFT JOIN sys.dm_exec_query_plan(r.plan_handle) qp ON 1 = 1
LEFT JOIN sys.partitions p ON r.resource_associated_entity_id = p.hobt_id
WHERE r.blocking_session_id <> 0 -- Only blocked sessions
ORDER BY r.start_time;