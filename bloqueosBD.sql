SELECT
    r.session_id AS [Session ID],
    r.status AS [Request Status],
    r.blocking_session_id AS [Blocked By],
    r.wait_type AS [Wait Type],
    r.wait_time AS [Wait Time (ms)],
    r.cpu_time AS [CPU Time (ms)],
    r.total_elapsed_time AS [Elapsed Time (ms)],
    t.text AS [SQL Text],
    DB_NAME(r.database_id) AS [Database],
    s.login_name AS [Login],
    s.host_name AS [Host Name],
    s.program_name AS [Program Name]
FROM
    sys.dm_exec_requests r
JOIN
    sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY
    sys.dm_exec_sql_text(r.sql_handle) t
WHERE
    r.blocking_session_id <> 0
ORDER BY
    r.total_elapsed_time DESC;