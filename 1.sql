SET NOCOUNT ON;

DECLARE @SampleSeconds INT = 10;
DECLARE @StartTime DATETIME2(3) = SYSDATETIME();
DECLARE @ElapsedSeconds DECIMAL(18,3);

DECLARE
    @BatchRequests0 BIGINT,
    @BatchRequests1 BIGINT,
    @Transactions0 BIGINT,
    @Transactions1 BIGINT;

-- =========================================================
-- 1. Primera muestra de contadores
-- =========================================================
SELECT @BatchRequests0 = cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:SQL Statistics%'
  AND counter_name = 'Batch Requests/sec';

SELECT @Transactions0 = cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%'
  AND counter_name = 'Transactions/sec'
  AND instance_name = '_Total';

-- =========================================================
-- 2. Primera muestra de I/O
-- =========================================================
DROP TABLE IF EXISTS #IO_Start;

SELECT
    database_id,
    file_id,
    num_of_reads,
    num_of_writes,
    num_of_bytes_read,
    num_of_bytes_written,
    io_stall_read_ms,
    io_stall_write_ms
INTO #IO_Start
FROM sys.dm_io_virtual_file_stats(NULL, NULL);

-- =========================================================
-- 3. Intervalo de medición
-- =========================================================
WAITFOR DELAY '00:00:10';

SET @ElapsedSeconds =
    DATEDIFF_BIG(MILLISECOND, @StartTime, SYSDATETIME()) / 1000.0;

-- =========================================================
-- 4. Segunda muestra de contadores
-- =========================================================
SELECT @BatchRequests1 = cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:SQL Statistics%'
  AND counter_name = 'Batch Requests/sec';

SELECT @Transactions1 = cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%'
  AND counter_name = 'Transactions/sec'
  AND instance_name = '_Total';

DROP TABLE IF EXISTS #IO_End;

SELECT
    database_id,
    file_id,
    num_of_reads,
    num_of_writes,
    num_of_bytes_read,
    num_of_bytes_written,
    io_stall_read_ms,
    io_stall_write_ms
INTO #IO_End
FROM sys.dm_io_virtual_file_stats(NULL, NULL);

-- =========================================================
-- 5. Throughput medido
-- =========================================================
SELECT
    @ElapsedSeconds AS Sample_Seconds,

    CAST(
        (@BatchRequests1 - @BatchRequests0)
        / NULLIF(@ElapsedSeconds, 0)
        AS DECIMAL(18,2)
    ) AS Batch_Requests_Per_Second,

    CAST(
        (@Transactions1 - @Transactions0)
        / NULLIF(@ElapsedSeconds, 0)
        AS DECIMAL(18,2)
    ) AS Transactions_Per_Second_Total,

    (
        SELECT COUNT(*)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    ) AS Logical_Schedulers,

    (
        SELECT COUNT(DISTINCT parent_node_id)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    ) AS NUMA_Nodes,

    (
        SELECT CAST(value_in_use AS INT)
        FROM sys.configurations
        WHERE name = 'max degree of parallelism'
    ) AS MaxDOP_Configured,

    (
        SELECT SUM(runnable_tasks_count)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    ) AS Runnable_Tasks_Total,

    (
        SELECT MAX(runnable_tasks_count)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    ) AS Runnable_Tasks_Max_Per_Scheduler;

-- =========================================================
-- 6. Memoria
-- =========================================================
SELECT
    osi.total_physical_memory_kb / 1024 AS OS_Total_Memory_MB,
    osm.available_physical_memory_kb / 1024 AS OS_Available_Memory_MB,

    osi.committed_kb / 1024 AS SQL_Committed_Memory_MB,
    osi.committed_target_kb / 1024 AS SQL_Target_Memory_MB,

    opm.physical_memory_in_use_kb / 1024 AS SQL_Process_Memory_MB,
    opm.process_physical_memory_low,
    opm.process_virtual_memory_low
FROM sys.dm_os_sys_info AS osi
CROSS JOIN sys.dm_os_sys_memory AS osm
CROSS JOIN sys.dm_os_process_memory AS opm;

-- =========================================================
-- 7. PLE global y por nodo NUMA
-- =========================================================
SELECT
    object_name,
    CASE
        WHEN instance_name = '' THEN 'Overall'
        ELSE instance_name
    END AS NUMA_Node,
    cntr_value AS Page_Life_Expectancy_Seconds
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
  AND (
        object_name LIKE '%:Buffer Manager%'
        OR object_name LIKE '%:Buffer Node%'
      )
ORDER BY object_name, instance_name;

-- =========================================================
-- 8. IOPS, throughput y latencia por archivo
-- =========================================================
SELECT
    DB_NAME(e.database_id) AS Database_Name,
    mf.type_desc AS File_Type,
    mf.name AS Logical_File_Name,
    mf.physical_name,

    CAST(
        (e.num_of_reads - s.num_of_reads)
        / NULLIF(@ElapsedSeconds, 0)
        AS DECIMAL(18,2)
    ) AS Read_IOPS,

    CAST(
        (e.num_of_writes - s.num_of_writes)
        / NULLIF(@ElapsedSeconds, 0)
        AS DECIMAL(18,2)
    ) AS Write_IOPS,

    CAST(
        (e.num_of_bytes_read - s.num_of_bytes_read)
        / 1048576.0
        / NULLIF(@ElapsedSeconds, 0)
        AS DECIMAL(18,2)
    ) AS Read_MB_Per_Second,

    CAST(
        (e.num_of_bytes_written - s.num_of_bytes_written)
        / 1048576.0
        / NULLIF(@ElapsedSeconds, 0)
        AS DECIMAL(18,2)
    ) AS Write_MB_Per_Second,

    CAST(
        (e.io_stall_read_ms - s.io_stall_read_ms) * 1.0
        / NULLIF(e.num_of_reads - s.num_of_reads, 0)
        AS DECIMAL(18,2)
    ) AS Average_Read_Latency_ms,

    CAST(
        (e.io_stall_write_ms - s.io_stall_write_ms) * 1.0
        / NULLIF(e.num_of_writes - s.num_of_writes, 0)
        AS DECIMAL(18,2)
    ) AS Average_Write_Latency_ms

FROM #IO_End AS e
INNER JOIN #IO_Start AS s
    ON s.database_id = e.database_id
   AND s.file_id = e.file_id
INNER JOIN sys.master_files AS mf
    ON mf.database_id = e.database_id
   AND mf.file_id = e.file_id
WHERE
    e.num_of_reads > s.num_of_reads
    OR e.num_of_writes > s.num_of_writes
ORDER BY
    (
        (e.num_of_reads - s.num_of_reads)
        + (e.num_of_writes - s.num_of_writes)
    ) DESC;