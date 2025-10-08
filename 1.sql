CREATE TABLE dbo.Monitoreo_UsoObjetos (
    FechaCaptura DATETIME NOT NULL DEFAULT GETDATE(),
    TipoObjeto NVARCHAR(50),
    Esquema NVARCHAR(128),
    NombreObjeto NVARCHAR(256),
    UltimoUso DATETIME NULL,
    VecesUsado BIGINT NULL,
    TotalCPU_ms BIGINT NULL,
    TotalTiempo_ms BIGINT NULL
);


INSERT INTO dbo.Monitoreo_UsoObjetos (TipoObjeto, Esquema, NombreObjeto, UltimoUso, VecesUsado, TotalCPU_ms, TotalTiempo_ms)
-- Procedimientos y funciones
SELECT 
    'Procedimiento/Función' AS TipoObjeto,
    OBJECT_SCHEMA_NAME(ps.object_id) AS Esquema,
    OBJECT_NAME(ps.object_id) AS NombreObjeto,
    ps.last_execution_time AS UltimoUso,
    ps.execution_count AS VecesUsado,
    ps.total_worker_time / 1000 AS TotalCPU_ms,
    ps.total_elapsed_time / 1000 AS TotalTiempo_ms
FROM sys.dm_exec_procedure_stats AS ps
WHERE ps.database_id = DB_ID()
UNION ALL
-- Vistas y tablas (a partir de índices usados)
SELECT 
    CASE o.type WHEN 'V' THEN 'Vista' ELSE 'Tabla' END AS TipoObjeto,
    s.name AS Esquema,
    o.name AS NombreObjeto,
    MAX(us.last_user_seek) AS UltimoUso,
    SUM(us.user_seeks + us.user_scans + us.user_lookups + us.user_updates) AS VecesUsado,
    NULL AS TotalCPU_ms,
    NULL AS TotalTiempo_ms
FROM sys.dm_db_index_usage_stats AS us
JOIN sys.objects AS o ON us.object_id = o.object_id
JOIN sys.schemas AS s ON o.schema_id = s.schema_id
WHERE us.database_id = DB_ID()
  AND o.type IN ('U', 'V')  -- U = tablas, V = vistas
GROUP BY s.name, o.name, o.type;



CREATE TABLE dbo.Monitoreo_Usuarios_Scripts (
    FechaCaptura DATETIME NOT NULL DEFAULT GETDATE(),
    Usuario SYSNAME,
    Host SYSNAME,
    BaseDatos SYSNAME,
    Estado NVARCHAR(50),
    InicioEjecucion DATETIME,
    Duracion_Segundos INT,
    ScriptEjecutado NVARCHAR(MAX),
    ComandoSQL NVARCHAR(200),
    CPU_ms INT,
    TiempoTotal_ms BIGINT
);

INSERT INTO dbo.Monitoreo_Usuarios_Scripts
(
    Usuario, Host, BaseDatos, Estado, InicioEjecucion, Duracion_Segundos,
    ScriptEjecutado, ComandoSQL, CPU_ms, TiempoTotal_ms
)
SELECT 
    s.login_name AS Usuario,
    s.host_name AS Host,
    DB_NAME(r.database_id) AS BaseDatos,
    r.status AS Estado,
    r.start_time AS InicioEjecucion,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS Duracion_Segundos,
    LEFT(st.text, 4000) AS ScriptEjecutado,  -- Limitamos tamaño por seguridad
    r.command AS ComandoSQL,
    r.cpu_time AS CPU_ms,
    r.total_elapsed_time AS TiempoTotal_ms
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE s.is_user_process = 1;


-- Mantener solo los últimos 30 días de registros
DELETE FROM dbo.Monitoreo_Usuarios_Scripts
WHERE FechaCaptura < DATEADD(DAY, -30, GETDATE());

DELETE FROM dbo.Monitoreo_UsoObjetos
WHERE FechaCaptura < DATEADD(DAY, -30, GETDATE());