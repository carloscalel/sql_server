SELECT
    r.session_id AS [Blocked Session ID],
    r.blocking_session_id AS [Blocking Session ID],
    DB_NAME(r.database_id) AS [Database],
    OBJECT_NAME(p.object_id, r.database_id) AS [Table Name],
    s.login_name AS [User],
    r.status AS [Request Status],
    r.wait_type,
    r.wait_time,
    r.command,
    t.text AS [SQL Text],
    s.host_name,
    s.program_name,
    r.start_time
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
LEFT JOIN sys.dm_os_waiting_tasks wt ON r.session_id = wt.session_id
LEFT JOIN sys.partitions p ON wt.resource_address = p.hobt_id
WHERE r.blocking_session_id <> 0
ORDER BY r.start_time;