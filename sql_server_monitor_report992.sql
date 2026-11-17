--------------------------------------------------------------------------------
-- MONITOR OPERATIVO SQL SERVER: RECURSOS, HISTORIAL Y COBERTURA
--------------------------------------------------------------------------------

USE msdb;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @CapturedAt DATETIME2(0) = SYSDATETIME();
DECLARE @WindowStart DATETIME = DATEADD(HOUR, -24, @CapturedAt), @WindowEnd DATETIME = @CapturedAt;
-- Umbrales operativos ajustables; no representan un diagnostico por si solos.
DECLARE @CpuWarning INT=80, @CpuCritical INT=95, @PleWarning INT=300,
    @MemoryWarning INT=85, @SpaceWarning INT=85, @SpaceCritical INT=95;
-- Excepciones previstas: agregar aqui bases en mantenimiento, con su motivo.
DECLARE @DatabaseStateExclusions TABLE(DatabaseName SYSNAME PRIMARY KEY, Reason NVARCHAR(256));
-- INSERT @DatabaseStateExclusions VALUES (N'BaseEnRestauracion', N'Mantenimiento programado');
IF OBJECT_ID('tempdb..#MonitorChecks') IS NOT NULL DROP TABLE #MonitorChecks;
CREATE TABLE #MonitorChecks(CheckName NVARCHAR(100) PRIMARY KEY, ReadOK BIT NULL, Details NVARCHAR(2048), CollectedAt DATETIME2(0));
IF OBJECT_ID('tempdb..#MonitorAlerts') IS NOT NULL DROP TABLE #MonitorAlerts;
CREATE TABLE #MonitorAlerts(Area NVARCHAR(100), Penalty INT, Detail NVARCHAR(2048));

DECLARE @ServerName NVARCHAR(128) = ISNULL(@@SERVERNAME, 'N/A');
DECLARE @InstanceName NVARCHAR(128) = ISNULL(@@SERVICENAME, 'N/A');
DECLARE @SQLVersion NVARCHAR(128) = ISNULL(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) + ' - ' + CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)), 'N/A');
DECLARE @ReportDate NVARCHAR(50) = ISNULL(CONVERT(NVARCHAR(30), @CapturedAt, 120), '');

BEGIN TRY
-- 1. Captura de CPU (SQL vs SO)
DECLARE @CpuSql INT, @CpuSo INT, @CpuSampleTime DATETIME2(0), @CpuSampleAgeSec INT;
SELECT TOP 1 
    @CpuSql = ISNULL(Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int'), 0),
    @CpuSo = 100 - ISNULL(Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'), 100)
FROM (
    SELECT TRY_CAST(record AS XML) AS Record, [timestamp] AS SampleTimestamp 
    FROM sys.dm_os_ring_buffers 
    WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
      AND record LIKE '%SystemHealth%'
) x
ORDER BY x.SampleTimestamp DESC;
SELECT @CpuSampleAgeSec = CONVERT(INT, (osi.ms_ticks - MAX(rb.[timestamp])) / 1000)
FROM sys.dm_os_sys_info osi CROSS JOIN sys.dm_os_ring_buffers rb
WHERE rb.ring_buffer_type=N'RING_BUFFER_SCHEDULER_MONITOR' AND rb.record LIKE '%SystemHealth%'
GROUP BY osi.ms_ticks;
SET @CpuSampleTime=DATEADD(SECOND,-@CpuSampleAgeSec,SYSDATETIME());


INSERT #MonitorChecks VALUES(N'CPU',CASE WHEN @CpuSql IS NULL OR @CpuSo IS NULL OR @CpuSampleAgeSec IS NULL OR @CpuSampleAgeSec>300 THEN 0 ELSE 1 END,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SELECT @CpuSql=NULL,@CpuSo=NULL,@CpuSampleTime=NULL;
INSERT #MonitorChecks VALUES(N'CPU',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

BEGIN TRY
-- 2. Page Life Expectancy (PLE)
DECLARE @PLE INT;
SELECT @PLE = ISNULL(cntr_value, 0) 
FROM sys.dm_os_performance_counters 
WHERE counter_name = N'Page life expectancy' 
  AND object_name LIKE N'%Buffer Manager%';


INSERT #MonitorChecks VALUES(N'PLE',CASE WHEN @PLE IS NULL THEN 0 ELSE 1 END,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SET @PLE=NULL;
INSERT #MonitorChecks VALUES(N'PLE',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

BEGIN TRY
-- 3. Memoria SO
DECLARE @TotalOSGB DECIMAL(10,2), @FreeOSGB DECIMAL(10,2), @UsedOSGB DECIMAL(10,2), @OSMemPct INT;
DECLARE @TotalOSKB BIGINT = 0;
SELECT 
    @TotalOSKB = total_physical_memory_kb,
    @TotalOSGB = ISNULL(CAST(total_physical_memory_kb / 1024.0 / 1024.0 AS DECIMAL(10,2)), 1),
    @FreeOSGB = ISNULL(CAST(available_physical_memory_kb / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    @UsedOSGB = ISNULL(CAST((total_physical_memory_kb - available_physical_memory_kb) / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    @OSMemPct = ISNULL(100 - CAST((CAST(available_physical_memory_kb AS FLOAT) / NULLIF(total_physical_memory_kb, 0) * 100) AS INT), 0)
FROM sys.dm_os_sys_memory;


INSERT #MonitorChecks VALUES(N'Memoria SO',CASE WHEN @TotalOSKB>0 THEN 1 ELSE 0 END,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SELECT @OSMemPct=NULL,@UsedOSGB=NULL,@TotalOSGB=NULL;
INSERT #MonitorChecks VALUES(N'Memoria SO',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

BEGIN TRY
-- 4. Memoria administrada por el motor y limite activo de max server memory.
-- Este limite no incluye todas las asignaciones del proceso sqlservr.exe.
DECLARE @SQLMemKB BIGINT, @SQLMemGB DECIMAL(10,2), @SQLMemPct INT;
DECLARE @SQLMaxMemMB BIGINT, @SQLMaxMemGB DECIMAL(12,2), @SQLMemoryPressure BIT;
SELECT
    @SQLMemKB = MAX(CASE WHEN counter_name LIKE N'Total Server Memory (KB%' THEN cntr_value END)
FROM sys.dm_os_performance_counters 
WHERE object_name LIKE N'%Memory Manager%';

SET @SQLMemGB = CAST(@SQLMemKB / 1024.0 / 1024.0 AS DECIMAL(10,2));
SELECT @SQLMaxMemMB = CONVERT(BIGINT, value_in_use)
FROM sys.configurations WHERE name = N'max server memory (MB)';
SELECT @SQLMemoryPressure = CASE WHEN process_physical_memory_low = 1 OR process_virtual_memory_low = 1 THEN 1 ELSE 0 END
FROM sys.dm_os_process_memory;

DECLARE @SQLMemPctBasis NVARCHAR(32) = N'de la RAM total';
DECLARE @SQLMemLimitText NVARCHAR(64) = N'no disponible';
IF @SQLMaxMemMB > 0 AND @SQLMaxMemMB < 2147483647
BEGIN
    SET @SQLMaxMemGB = CAST(@SQLMaxMemMB / 1024.0 AS DECIMAL(12,2));
    SET @SQLMemPct = CAST(ROUND(@SQLMemKB * 100.0 / (@SQLMaxMemMB * 1024.0), 0) AS INT);
    SET @SQLMemPctBasis = N'del límite configurado';
    SET @SQLMemLimitText = CONCAT(CAST(@SQLMaxMemGB AS VARCHAR(20)), N' GiB');
END
ELSE
BEGIN
    -- El valor predeterminado no representa una reserva real de millones de GiB.
    SET @SQLMemPct = CAST(ROUND(@SQLMemKB * 100.0 / NULLIF(@TotalOSKB, 0), 0) AS INT);
    IF @SQLMaxMemMB IN (0, 2147483647)
        SET @SQLMemLimitText = N'sin configurar';
END;

DECLARE @SQLMemStatus NVARCHAR(20) = CASE WHEN @SQLMemoryPressure = 1 THEN N'PRESIÓN'
    WHEN @SQLMemoryPressure = 0 AND @SQLMemKB IS NOT NULL THEN N'NORMAL' ELSE N'SIN DATOS' END;
DECLARE @SQLMemStatusColor VARCHAR(7) = CASE WHEN @SQLMemoryPressure = 1 THEN '#dc3545'
    WHEN @SQLMemoryPressure = 0 AND @SQLMemKB IS NOT NULL THEN '#28a745' ELSE '#6c757d' END;


INSERT #MonitorChecks VALUES(N'Memoria SQL',CASE WHEN @SQLMemKB IS NOT NULL AND @SQLMemoryPressure IS NOT NULL AND @SQLMaxMemMB IS NOT NULL THEN 1 ELSE 0 END,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SELECT @SQLMemKB=NULL,@SQLMemGB=NULL,@SQLMemPct=NULL,@SQLMemStatus=N'SIN DATOS',@SQLMemStatusColor='#6c757d';
INSERT #MonitorChecks VALUES(N'Memoria SQL',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

BEGIN TRY
-- 5. Transacciones Abiertas
IF OBJECT_ID('tempdb..#ActiveTransList') IS NOT NULL DROP TABLE #ActiveTransList;
CREATE TABLE #ActiveTransList (
    SessionID INT,
    LoginName NVARCHAR(128),
    DatabaseName NVARCHAR(128),
    TransactionDurationSec INT
);

INSERT INTO #ActiveTransList (SessionID, LoginName, DatabaseName, TransactionDurationSec)
SELECT DISTINCT 
    s.session_id,
    ISNULL(s.login_name, 'N/A') AS LoginName,
    ISNULL(DB_NAME(dt.database_id), ISNULL(DB_NAME(s.database_id), 'N/A')) AS DatabaseName,
    DATEDIFF(SECOND, t.transaction_begin_time, GETDATE()) AS TransactionDurationSec
FROM sys.dm_tran_active_transactions t
JOIN sys.dm_tran_session_transactions st ON t.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
LEFT JOIN sys.dm_tran_database_transactions dt ON t.transaction_id = dt.transaction_id
WHERE s.session_id <> @@SPID AND s.is_user_process=1 AND st.is_user_transaction=1;

DECLARE @ActiveTransCount INT;
SELECT @ActiveTransCount = COUNT(1) FROM #ActiveTransList;


INSERT #MonitorChecks VALUES(N'Transacciones',1,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SET @ActiveTransCount=NULL;
INSERT #MonitorChecks VALUES(N'Transacciones',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

BEGIN TRY
-- 6. Bloqueos y Sesiones Bloqueadas
IF OBJECT_ID('tempdb..#BlockedList') IS NOT NULL DROP TABLE #BlockedList;
CREATE TABLE #BlockedList (
    BlockedSPID INT,
    BlockingSPID INT,
    DatabaseName NVARCHAR(128),
    WaitTimeMs INT,
    LastQuery NVARCHAR(MAX)
);

INSERT INTO #BlockedList (BlockedSPID, BlockingSPID, DatabaseName, WaitTimeMs, LastQuery)
SELECT 
    r.session_id,
    r.blocking_session_id,
    ISNULL(DB_NAME(r.database_id), ISNULL(DB_NAME(s.database_id), 'N/A')),
    r.wait_time,
    ISNULL(qt.text, 'N/A')
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) qt
WHERE r.blocking_session_id <> 0;

DECLARE @BlockedSessionsCount INT;
SELECT @BlockedSessionsCount = COUNT(1) FROM #BlockedList;


INSERT #MonitorChecks VALUES(N'Bloqueos',1,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SET @BlockedSessionsCount=NULL;
INSERT #MonitorChecks VALUES(N'Bloqueos',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

BEGIN TRY
-- 7. SQL Agent Jobs Fallidos (Últimas 24 horas)
IF OBJECT_ID('tempdb..#FailedJobs') IS NOT NULL DROP TABLE #FailedJobs;
CREATE TABLE #FailedJobs (
    JobName SYSNAME,
    RunDateTime DATETIME2(0),
    Message NVARCHAR(MAX)
);

INSERT INTO #FailedJobs (JobName, RunDateTime, Message)
SELECT 
    ISNULL(j.name, 'Desconocido'),
    execution.RunDateTime,
    ISNULL(h.message, '')
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
-- Construir una fecha ISO completa. Insertar en la posicion 11 de una fecha
-- de 10 caracteres con STUFF devolvia NULL y dejaba vacia la celda del reporte.
CROSS APPLY (VALUES (TRY_CONVERT(DATETIME2(0),
    STUFF(STUFF(CAST(h.run_date AS CHAR(8)), 5, 0, '-'), 8, 0, '-') + 'T' +
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':'),
    126))) execution(RunDateTime)
WHERE h.run_status = 0 
  AND h.step_id = 0 
  AND execution.RunDateTime >= @WindowStart AND execution.RunDateTime <= @WindowEnd;

DECLARE @FailedJobsCount INT;
SELECT @FailedJobsCount = ISNULL(COUNT(1), 0) FROM #FailedJobs;


INSERT #MonitorChecks VALUES(N'Jobs',1,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SET @FailedJobsCount=NULL;
INSERT #MonitorChecks VALUES(N'Jobs',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

-- 7b. Integration Services: ejecuciones fallidas y errores originales de SSISDB.
-- La consulta dinamica evita errores de compilacion en instancias sin catalogo.
IF OBJECT_ID('tempdb..#FailedSsis') IS NOT NULL DROP TABLE #FailedSsis;
CREATE TABLE #FailedSsis (
    ExecutionID BIGINT PRIMARY KEY,
    FolderName SYSNAME,
    ProjectName SYSNAME,
    PackageName NVARCHAR(260),
    ErrorPackage NVARCHAR(260),
    ErrorSource NVARCHAR(4000),
    StartDateTime DATETIMEOFFSET(7),
    FailureDateTime DATETIMEOFFSET(7),
    ExecutionStatus INT,
    Message NVARCHAR(MAX)
);

DECLARE @SsisWindowEnd DATETIMEOFFSET(7) = TODATETIMEOFFSET(@CapturedAt, DATENAME(TZOFFSET,SYSDATETIMEOFFSET()));
DECLARE @FailedSsisCount INT = 0, @SsisCatalogRead BIT = 0;
DECLARE @SsisNotice NVARCHAR(MAX) = N'';

IF DB_ID(N'SSISDB') IS NULL
    SET @SsisNotice = N'No existe el catálogo SSISDB en esta instancia. No se pudo consultar el historial de paquetes.';
ELSE IF ISNULL(HAS_DBACCESS(N'SSISDB'), 0) <> 1
    SET @SsisNotice = N'No se pudo acceder a SSISDB. Verifique el estado del catálogo y los permisos de la cuenta que genera el reporte.';
ELSE
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql N'
            INSERT INTO #FailedSsis (ExecutionID, FolderName, ProjectName, PackageName,
                ErrorPackage, ErrorSource, StartDateTime, FailureDateTime, ExecutionStatus, Message)
            SELECT e.execution_id, e.folder_name, e.project_name, e.package_name,
                detail.package_name, detail.message_source_name, e.start_time, e.end_time, e.status,
                COALESCE(NULLIF(detail.message, N''''), NULLIF(operation.message, N''''),
                    N''SSISDB no conserva un mensaje de error para esta ejecución. Consulte el ID de ejecución en el catálogo.'')
            FROM [SSISDB].[catalog].[executions] e
            OUTER APPLY (
                -- El primer Error suele preceder los mensajes de propagacion del fallo.
                -- Conservar el texto completo y el componente/paquete que lo origino.
                SELECT TOP (1) em.package_name, em.message_source_name, em.message
                FROM [SSISDB].[catalog].[event_messages] em
                WHERE em.operation_id = e.execution_id AND em.message_type = 120
                  AND NULLIF(em.message, N'''') IS NOT NULL
                ORDER BY em.message_time, em.event_message_id
            ) detail
            OUTER APPLY (
                -- Algunos errores del servidor no tienen un evento de paquete asociado.
                SELECT TOP (1) om.message
                FROM [SSISDB].[catalog].[operation_messages] om
                WHERE om.operation_id = e.execution_id AND om.message_type = 120
                  AND NULLIF(om.message, N'''') IS NOT NULL AND detail.message IS NULL
                ORDER BY om.message_time, om.operation_message_id
            ) operation
            WHERE e.status IN (4, 6)
              AND e.end_time >= DATEADD(HOUR, -24, @WindowEnd)
              AND e.end_time <= @WindowEnd;',
            N'@WindowEnd DATETIMEOFFSET(7)', @WindowEnd = @SsisWindowEnd;
        SET @SsisCatalogRead = 1;
    END TRY
    BEGIN CATCH
        SET @SsisNotice = CONCAT(N'No se pudo consultar SSISDB: ', ERROR_MESSAGE());
    END CATCH;
END;

SELECT @FailedSsisCount = COUNT(*) FROM #FailedSsis;
INSERT #MonitorChecks VALUES(N'SSISDB', CASE WHEN DB_ID(N'SSISDB') IS NULL THEN NULL ELSE @SsisCatalogRead END, @SsisNotice, SYSDATETIME());

-- 8. Errores relevantes: cabeceras estructuradas, no palabras genericas.
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;
CREATE TABLE #ErrorLog(LogDate DATETIME, ProcessInfo NVARCHAR(50), Text NVARCHAR(MAX));
IF OBJECT_ID('tempdb..#ErrorArchives') IS NOT NULL DROP TABLE #ErrorArchives;
CREATE TABLE #ErrorArchives(ArchiveNo INT, LogDate DATETIME, LogSize BIGINT);
DECLARE @ErrorLogRead BIT=1, @ErrorNotice NVARCHAR(2048)=N'', @ArchiveNo INT;
BEGIN TRY
    INSERT #ErrorArchives EXEC master.dbo.xp_enumerrorlogs;
END TRY
BEGIN CATCH
    SET @ErrorLogRead=0; SET @ErrorNotice=ERROR_MESSAGE();
    INSERT #ErrorArchives VALUES(0,NULL,NULL);
END CATCH;
DECLARE errorArchiveCursor CURSOR LOCAL FAST_FORWARD FOR SELECT ArchiveNo FROM #ErrorArchives ORDER BY ArchiveNo;
OPEN errorArchiveCursor;
FETCH NEXT FROM errorArchiveCursor INTO @ArchiveNo;
WHILE @@FETCH_STATUS=0
BEGIN
    BEGIN TRY
        INSERT #ErrorLog EXEC master.dbo.xp_readerrorlog @ArchiveNo,1,NULL,NULL,@WindowStart,@WindowEnd,N'asc';
    END TRY
    BEGIN CATCH
        SET @ErrorLogRead=0; SET @ErrorNotice=CONCAT(N'Archivo ',@ArchiveNo,N': ',ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM errorArchiveCursor INTO @ArchiveNo;
END;
CLOSE errorArchiveCursor; DEALLOCATE errorArchiveCursor;
IF OBJECT_ID('tempdb..#CriticalErrorLog') IS NOT NULL DROP TABLE #CriticalErrorLog;
CREATE TABLE #CriticalErrorLog(LogDate DATETIME, ErrorNumber INT NULL, Severity INT NULL, Message NVARCHAR(MAX));
INSERT #CriticalErrorLog
SELECT el.LogDate, parsed.ErrorNumber, parsed.Severity, el.Text
FROM #ErrorLog el
CROSS APPLY(VALUES(LOWER(LTRIM(el.Text)))) normalized(txt)
CROSS APPLY(VALUES(CASE WHEN normalized.txt LIKE N'error:%' THEN LTRIM(SUBSTRING(normalized.txt,7,30)) END,
    CASE WHEN CHARINDEX(N'severity:',normalized.txt)>0 THEN LTRIM(SUBSTRING(normalized.txt,CHARINDEX(N'severity:',normalized.txt)+9,20))
         WHEN CHARINDEX(N'severidad:',normalized.txt)>0 THEN LTRIM(SUBSTRING(normalized.txt,CHARINDEX(N'severidad:',normalized.txt)+10,20))
         WHEN CHARINDEX(N'gravedad:',normalized.txt)>0 THEN LTRIM(SUBSTRING(normalized.txt,CHARINDEX(N'gravedad:',normalized.txt)+9,20)) END)) tokens(err,sev)
CROSS APPLY(VALUES(TRY_CONVERT(INT,LEFT(tokens.err,CHARINDEX(N',',tokens.err+N',')-1)),TRY_CONVERT(INT,LEFT(tokens.sev,CHARINDEX(N',',tokens.sev+N',')-1)))) parsed(ErrorNumber,Severity)
WHERE el.LogDate>=@WindowStart AND el.LogDate<=@WindowEnd
AND (parsed.Severity>=20 OR parsed.ErrorNumber IN(823,824,825,701,802,9002,1101,1105)
    OR normalized.txt LIKE N'%sql server assertion:%');
DECLARE @CriticalErrorsCount INT;
SELECT @CriticalErrorsCount=COUNT(*) FROM #CriticalErrorLog;
INSERT #MonitorChecks VALUES(N'Error Log',@ErrorLogRead,@ErrorNotice,SYSDATETIME());

BEGIN TRY
-- 9. Consultas de Larga Duración (> 5 minutos)
IF OBJECT_ID('tempdb..#LongQueries') IS NOT NULL DROP TABLE #LongQueries;
CREATE TABLE #LongQueries (
    SessionID INT,
    LoginName NVARCHAR(128),
    DatabaseName NVARCHAR(128),
    ElapsedMinutes INT,
    Command NVARCHAR(32)
);

INSERT INTO #LongQueries (SessionID, LoginName, DatabaseName, ElapsedMinutes, Command)
SELECT TOP 5
    ISNULL(r.session_id, 0),
    ISNULL(s.login_name, 'N/A'),
    ISNULL(DB_NAME(r.database_id), ISNULL(DB_NAME(s.database_id), 'N/A')),
    ISNULL(CAST(r.total_elapsed_time / 1000.0 / 60.0 AS INT), 0),
    ISNULL(r.command, '')
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
WHERE r.total_elapsed_time > 300000 
  AND r.session_id <> @@SPID
  AND r.status <> 'background'
ORDER BY r.total_elapsed_time DESC;

DECLARE @LongQueriesCount INT;
SELECT @LongQueriesCount = ISNULL(COUNT(1), 0) FROM #LongQueries;


INSERT #MonitorChecks VALUES(N'Consultas largas',1,N'',SYSDATETIME());
END TRY
BEGIN CATCH
SET @LongQueriesCount=NULL;
INSERT #MonitorChecks VALUES(N'Consultas largas',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

-- 10. El puntaje se calcula despues de completar todas las capturas.

BEGIN TRY
-- 11. Capacidad del volumen completo en GiB (1024^3), una fila por volumen.
-- Solo se incluyen los volúmenes que contienen archivos de esta instancia.
IF OBJECT_ID('tempdb..#Disks') IS NOT NULL DROP TABLE #Disks;
CREATE TABLE #Disks (
    RowID INT PRIMARY KEY,
    VolumeName NVARCHAR(512),
    TotalGiB DECIMAL(10,2),
    FreeGiB DECIMAL(10,2),
    UsedGiB DECIMAL(10,2),
    UsedPct INT,
    DiskStatus VARCHAR(20)
);

;WITH VolumeSpace AS (
    SELECT
        ISNULL(vs.volume_mount_point, N'N/A') AS VolumeName,
        MAX(vs.total_bytes) AS TotalBytes,
        -- El espacio libre puede variar entre lecturas: conservar la menor lectura.
        MIN(vs.available_bytes) AS FreeBytes
    FROM sys.master_files mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
    GROUP BY ISNULL(vs.volume_mount_point, N'N/A')
)
INSERT INTO #Disks (RowID, VolumeName, TotalGiB, FreeGiB, UsedGiB, UsedPct, DiskStatus)
SELECT
    CAST(ROW_NUMBER() OVER (ORDER BY VolumeName) AS INT),
    VolumeName,
    ISNULL(CAST(TotalBytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    ISNULL(CAST(FreeBytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    ISNULL(CAST((TotalBytes - FreeBytes) / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    ISNULL(CAST((TotalBytes - FreeBytes) * 100.0 / NULLIF(TotalBytes, 0) AS INT), 0),
    CASE WHEN ISNULL(FreeBytes * 100.0 / NULLIF(TotalBytes, 0), 100) < 15 THEN 'CRITICO' ELSE 'NORMAL' END
FROM VolumeSpace;


INSERT #MonitorChecks VALUES(N'Discos',CASE WHEN EXISTS(SELECT 1 FROM #Disks) THEN 1 ELSE 0 END,N'',SYSDATETIME());
END TRY
BEGIN CATCH

INSERT #MonitorChecks VALUES(N'Discos',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

-- 11b. Estado de bases y exclusiones previstas.
IF OBJECT_ID('tempdb..#DatabaseHealth') IS NOT NULL DROP TABLE #DatabaseHealth;
CREATE TABLE #DatabaseHealth(DatabaseID INT PRIMARY KEY, DatabaseName SYSNAME, StateDesc NVARCHAR(60), RecoveryModel NVARCHAR(60), LogReuseWait NVARCHAR(60), IsSnapshot BIT, Exclusion NVARCHAR(256));
BEGIN TRY
    INSERT #DatabaseHealth
    SELECT d.database_id,d.name,d.state_desc,d.recovery_model_desc,d.log_reuse_wait_desc,
        CASE WHEN d.source_database_id IS NULL THEN 0 ELSE 1 END,x.Reason
    FROM sys.databases d LEFT JOIN @DatabaseStateExclusions x ON x.DatabaseName=d.name;
    INSERT #MonitorChecks VALUES(N'Estado de bases',CASE WHEN HAS_PERMS_BY_NAME(NULL,N'SERVER',N'VIEW ANY DATABASE')=1 OR IS_SRVROLEMEMBER(N'sysadmin')=1 THEN 1 ELSE 0 END,
        N'La enumeración completa requiere visibilidad de todas las bases.',SYSDATETIME());
END TRY
BEGIN CATCH
    INSERT #MonitorChecks VALUES(N'Estado de bases',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

-- 11c. Espacio asignado a archivos de datos de TEMPDB (MiB).
IF OBJECT_ID('tempdb..#TempdbSpace') IS NOT NULL DROP TABLE #TempdbSpace;
CREATE TABLE #TempdbSpace(TotalMB DECIMAL(18,2), UsedMB DECIMAL(18,2), FreeMB DECIMAL(18,2), VersionMB DECIMAL(18,2), UserMB DECIMAL(18,2), InternalMB DECIMAL(18,2), UsedPct DECIMAL(9,2));
BEGIN TRY
    INSERT #TempdbSpace EXEC sys.sp_executesql N'USE tempdb;
        SELECT SUM(CONVERT(BIGINT,total_page_count))*8.0/1024,
            SUM(CONVERT(BIGINT,total_page_count)-unallocated_extent_page_count)*8.0/1024,
            SUM(CONVERT(BIGINT,unallocated_extent_page_count))*8.0/1024,
            SUM(CONVERT(BIGINT,version_store_reserved_page_count))*8.0/1024,
            SUM(CONVERT(BIGINT,user_object_reserved_page_count))*8.0/1024,
            SUM(CONVERT(BIGINT,internal_object_reserved_page_count))*8.0/1024,
            SUM(CONVERT(BIGINT,total_page_count)-unallocated_extent_page_count)*100.0/NULLIF(SUM(CONVERT(BIGINT,total_page_count)),0)
        FROM sys.dm_db_file_space_usage;';
    INSERT #MonitorChecks VALUES(N'TEMPDB',CASE WHEN EXISTS(SELECT 1 FROM #TempdbSpace WHERE TotalMB>0) THEN 1 ELSE 0 END,N'',SYSDATETIME());
END TRY
BEGIN CATCH
    INSERT #MonitorChecks VALUES(N'TEMPDB',0,ERROR_MESSAGE(),SYSDATETIME());
END CATCH;

-- 11d. LOG: espacio dentro de los archivos, no espacio libre del volumen.
IF OBJECT_ID('tempdb..#DatabaseLog') IS NOT NULL DROP TABLE #DatabaseLog;
CREATE TABLE #DatabaseLog(DatabaseName SYSNAME, TotalMB DECIMAL(18,2), UsedMB DECIMAL(18,2), FreeMB DECIMAL(18,2), UsedPct DECIMAL(9,2), ReuseWait NVARCHAR(60), ReadOK BIT NULL, Details NVARCHAR(2048));
DECLARE @LogDB SYSNAME,@LogState NVARCHAR(60),@LogReuse NVARCHAR(60),@LogSnapshot BIT,@LogQuery NVARCHAR(MAX);
DECLARE databaseLogCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DatabaseName,StateDesc,LogReuseWait,IsSnapshot FROM #DatabaseHealth ORDER BY DatabaseName;
OPEN databaseLogCursor;
FETCH NEXT FROM databaseLogCursor INTO @LogDB,@LogState,@LogReuse,@LogSnapshot;
WHILE @@FETCH_STATUS=0
BEGIN
    IF @LogSnapshot=1
        INSERT #DatabaseLog VALUES(@LogDB,NULL,NULL,NULL,NULL,@LogReuse,NULL,N'NO APLICA: instantánea de base de datos.');
    ELSE IF @LogState<>N'ONLINE'
        INSERT #DatabaseLog VALUES(@LogDB,NULL,NULL,NULL,NULL,@LogReuse,NULL,CONCAT(N'NO DISPONIBLE: base ',@LogState));
    ELSE
    BEGIN
        BEGIN TRY
            SET @LogQuery=N'USE '+QUOTENAME(@LogDB)+N';
                INSERT #DatabaseLog(DatabaseName,TotalMB,UsedMB,FreeMB,UsedPct,ReuseWait,ReadOK,Details)
                SELECT @DB,total_log_size_in_bytes/1048576.0,used_log_space_in_bytes/1048576.0,
                    (total_log_size_in_bytes-used_log_space_in_bytes)/1048576.0,used_log_space_in_percent,@Reuse,1,N''''
                FROM sys.dm_db_log_space_usage;';
            EXEC sys.sp_executesql @LogQuery,N'@DB SYSNAME,@Reuse NVARCHAR(60)',@DB=@LogDB,@Reuse=@LogReuse;
            IF NOT EXISTS(SELECT 1 FROM #DatabaseLog WHERE DatabaseName=@LogDB)
                INSERT #DatabaseLog VALUES(@LogDB,NULL,NULL,NULL,NULL,@LogReuse,0,N'SIN DATOS: la consulta no devolvió mediciones.');
        END TRY
        BEGIN CATCH
            INSERT #DatabaseLog VALUES(@LogDB,NULL,NULL,NULL,NULL,@LogReuse,0,ERROR_MESSAGE());
        END CATCH;
    END;
    FETCH NEXT FROM databaseLogCursor INTO @LogDB,@LogState,@LogReuse,@LogSnapshot;
END;
CLOSE databaseLogCursor; DEALLOCATE databaseLogCursor;
INSERT #MonitorChecks
SELECT N'LOG',CASE WHEN EXISTS(SELECT 1 FROM #MonitorChecks WHERE CheckName=N'Estado de bases' AND ReadOK=1)
    AND NOT EXISTS(SELECT 1 FROM #DatabaseLog WHERE ReadOK=0) AND EXISTS(SELECT 1 FROM #DatabaseLog WHERE ReadOK=1) THEN 1 ELSE 0 END,
    N'Cobertura y causas por base en la sección LOG. Bases no disponibles e instantáneas se muestran por separado.',SYSDATETIME();

-- 11e. Alertas explicitas: umbrales comunes para tarjetas y puntaje.
INSERT #MonitorAlerts
SELECT N'CPU',CASE WHEN @CpuSql>=@CpuCritical OR @CpuSo>=@CpuCritical THEN 20 ELSE 10 END,
    CONCAT(N'CPU SQL: ',@CpuSql,N'%; CPU SO (total del sistema): ',@CpuSo,N'%.')
WHERE (@CpuSql>=@CpuWarning OR @CpuSo>=@CpuWarning) AND EXISTS(SELECT 1 FROM #MonitorChecks WHERE CheckName=N'CPU' AND ReadOK=1);
INSERT #MonitorAlerts SELECT N'PLE',15,CONCAT(N'PLE por debajo del umbral configurado de ',@PleWarning,N' segundos: ',@PLE,N'.') WHERE @PLE<@PleWarning;
INSERT #MonitorAlerts SELECT N'Memoria SO',20,CONCAT(N'RAM utilizada: ',@OSMemPct,N'%.') WHERE @OSMemPct>@MemoryWarning;
INSERT #MonitorAlerts SELECT N'Memoria SQL',20,N'SQL Server informa presión de memoria.' WHERE @SQLMemoryPressure=1;
INSERT #MonitorAlerts SELECT N'Consultas largas',10,CONCAT(N'Se muestran hasta 5 consultas de más de 5 minutos; encontradas: ',@LongQueriesCount,N'.') WHERE @LongQueriesCount>0;
INSERT #MonitorAlerts SELECT N'Transacciones',10,CONCAT(COUNT(DISTINCT SessionID),N' sesiones de usuario con transacciones de más de 5 minutos.') FROM #ActiveTransList WHERE TransactionDurationSec>300 HAVING COUNT(DISTINCT SessionID)>0;
INSERT #MonitorAlerts SELECT N'Bloqueos',CASE WHEN @BlockedSessionsCount>3 THEN 30 ELSE @BlockedSessionsCount*10 END,CONCAT(@BlockedSessionsCount,N' sesiones bloqueadas al consultar.') WHERE @BlockedSessionsCount>0;
-- Jobs y SSIS pueden describir el mismo incidente: una penalizacion de ejecuciones, no una por cada fuente.
IF @FailedJobsCount>0 OR @FailedSsisCount>0
    INSERT #MonitorAlerts VALUES(N'Ejecuciones',15,CONCAT(N'Últimas 24h: ',COALESCE(CONVERT(NVARCHAR(12),@FailedJobsCount),N'N/D'),N' ejecuciones de jobs fallidas y ',CASE WHEN @SsisCatalogRead=1 THEN CONVERT(NVARCHAR(12),@FailedSsisCount) ELSE N'N/D' END,N' ejecuciones SSIS fallidas. Se aplica una única penalización a esta categoría.'));
INSERT #MonitorAlerts SELECT N'Error Log',25,CONCAT(@CriticalErrorsCount,N' cabeceras de errores relevantes o aserciones en el historial disponible de 24h.') WHERE @CriticalErrorsCount>0;
INSERT #MonitorAlerts SELECT N'Discos',25,CONCAT(N'Volumen ',VolumeName,N': ',UsedPct,N'% ocupado.') FROM #Disks WHERE DiskStatus=N'CRITICO';
INSERT #MonitorAlerts SELECT N'Bases',CASE WHEN StateDesc IN(N'SUSPECT',N'RECOVERY_PENDING',N'EMERGENCY') THEN 40 ELSE 15 END,
    CONCAT(DatabaseName,N': ',StateDesc,N'.') FROM #DatabaseHealth WHERE StateDesc<>N'ONLINE' AND Exclusion IS NULL;
INSERT #MonitorAlerts SELECT N'TEMPDB',CASE WHEN UsedPct>=@SpaceCritical THEN 25 ELSE 10 END,CONCAT(N'TEMPDB: ',UsedPct,N'% de datos asignados ocupado; versiones: ',VersionMB,N' MiB.') FROM #TempdbSpace WHERE UsedPct>=@SpaceWarning;
INSERT #MonitorAlerts SELECT N'LOG',CASE WHEN UsedPct>=@SpaceCritical THEN 25 ELSE 10 END,CONCAT(DatabaseName,N': LOG ',UsedPct,N'% ocupado; reutilización: ',ReuseWait,N'.') FROM #DatabaseLog WHERE ReadOK=1 AND UsedPct>=@SpaceWarning;
DECLARE @MissingChecks INT=(SELECT COUNT(*) FROM #MonitorChecks WHERE ReadOK=0);
DECLARE @HealthScore INT=100-(SELECT ISNULL(SUM(Penalty),0) FROM #MonitorAlerts);
IF @HealthScore<0 SET @HealthScore=0;
DECLARE @StatusText VARCHAR(50),@StatusColor VARCHAR(20);
SELECT @StatusText=CASE WHEN @HealthScore<60 THEN 'CRITICO' WHEN @MissingChecks>0 THEN 'DATOS INCOMPLETOS' WHEN EXISTS(SELECT 1 FROM #MonitorAlerts) THEN 'REQUIERE ATENCION' ELSE 'ESTABLE' END,
    @StatusColor=CASE WHEN @HealthScore<60 THEN '#dc3545' WHEN @MissingChecks>0 OR EXISTS(SELECT 1 FROM #MonitorAlerts) THEN '#b77900' ELSE '#28a745' END;
DECLARE @CpuSqlStatus NVARCHAR(20),@CpuSoStatus NVARCHAR(20),@CpuSqlColor VARCHAR(7),@CpuSoColor VARCHAR(7);
SELECT @CpuSqlStatus=CASE WHEN @CpuSql IS NULL OR EXISTS(SELECT 1 FROM #MonitorChecks WHERE CheckName=N'CPU' AND ReadOK=0) THEN N'SIN DATOS' WHEN @CpuSql>=@CpuCritical THEN N'CRITICO' WHEN @CpuSql>=@CpuWarning THEN N'ALERTA' ELSE N'NORMAL' END,
    @CpuSoStatus=CASE WHEN @CpuSo IS NULL OR EXISTS(SELECT 1 FROM #MonitorChecks WHERE CheckName=N'CPU' AND ReadOK=0) THEN N'SIN DATOS' WHEN @CpuSo>=@CpuCritical THEN N'CRITICO' WHEN @CpuSo>=@CpuWarning THEN N'ALERTA' ELSE N'NORMAL' END;
SELECT @CpuSqlColor=CASE @CpuSqlStatus WHEN N'SIN DATOS' THEN '#6c757d' WHEN N'CRITICO' THEN '#dc3545' WHEN N'ALERTA' THEN '#b77900' ELSE '#28a745' END,
    @CpuSoColor=CASE @CpuSoStatus WHEN N'SIN DATOS' THEN '#6c757d' WHEN N'CRITICO' THEN '#dc3545' WHEN N'ALERTA' THEN '#b77900' ELSE '#28a745' END;


-- 12. Construcción del HTML con Estructura Rígida y Segura
DECLARE @Html NVARCHAR(MAX) = N'';

-- HTML PARTE 1: HEADER, SCORECARD Y MÉTRICAS (2 FILAS x 3 COLUMNAS DE IGUAL ANCHO)
-- CONCAT debe recibir un argumento MAX para no truncar el HTML a 8.000 caracteres.
-- Asignar el resultado a @Html NVARCHAR(MAX) por sí solo no evita ese recorte.
SET @Html = CONCAT(
CAST(N'' AS NVARCHAR(MAX)),
N'<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Monitor Operativo SQL Server</title>
</head>
<body style="margin:0; padding:0; background-color:#f4f6f9; font-family: Arial, sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f6f9; padding: 20px;">
  <tr>
    <td align="center">
      <!-- CONTENEDOR MAESTRO DE 660px -->
      <table width="660" cellpadding="0" cellspacing="0" border="0" style="background-color:#ffffff; border-radius: 6px; overflow:hidden; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">
        
        <!-- HEADER -->
        <tr>
          <td style="background-color: #1e3d59; color: #ffffff; padding: 20px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td>
                  <h2 style="margin: 0; font-size: 20px; font-weight: bold;">MONITOR OPERATIVO SQL SERVER</h2>
                  <p style="margin: 5px 0 0 0; font-size: 13px; color: #b8c1ec;">
                    Servidor: <b>', @ServerName, '</b> | Instancia: <b>', @InstanceName, '</b><br>
                    Versión: ', @SQLVersion, '<br>
                    Fecha: ', @ReportDate, '
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- SCORECARD -->
        <tr>
          <td align="center" style="padding: 20px; background-color: #f8f9fa; border-bottom: 1px solid #e9ecef;">
            <table cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td align="center">
                  <span style="font-size: 42px; font-weight: bold; color: ', @StatusColor, ';">', CASE WHEN @MissingChecks>0 THEN 'N/D' ELSE CAST(@HealthScore AS VARCHAR(3)) END, '</span><br>
                  <span style="font-size: 12px; font-weight: bold; color: ', @StatusColor, '; letter-spacing: 1px;">', @StatusText, '</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr><td style="padding: 10px 20px; font-size: 10px; color: #6c757d;">
          Captura: ',CONVERT(VARCHAR(19),@CapturedAt,120),'. Ventana histórica: ',CONVERT(VARCHAR(19),@WindowStart,120),' a ',CONVERT(VARCHAR(19),@WindowEnd,120),' (hora del servidor).<br>
          Memoria, PLE, discos, bases, TEMPDB, LOG, transacciones y bloqueos: fotografía durante la captura. Jobs, SSIS y Error Log: historial disponible de 24h.<br>
          CPU: última muestra del monitor, ',ISNULL(CONVERT(VARCHAR(19),@CpuSampleTime,120),'no disponible'),' (edad: ',COALESCE(CONVERT(VARCHAR(12),@CpuSampleAgeSec),'N/D'),' s). CPU SO incluye la CPU de SQL; los porcentajes no se suman.<br>
          Puntaje orientativo: parte de 100 y resta las penalizaciones del resumen. Si faltan controles se muestra N/D; las alertas conocidas siguen visibles.
        </td></tr>
        <!-- MÉTRICAS CLAVE: 2 FILAS x 3 COLUMNAS CON CONTENEDORES INDIVIDUALES -->
        <tr>
          <td style="padding: 15px 15px 5px 15px;">
            <table width="100%" cellpadding="0" cellspacing="5" border="0" style="table-layout: fixed; border-collapse: separate; border-spacing: 5px;">
              <!-- FILA 1 -->
              <tr>
                <td width="33.33%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px; vertical-align: top;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">CPU SQL</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CASE WHEN @CpuSql IS NULL THEN 'N/D' ELSE CONCAT(@CpuSql, '%') END, '</span><br>
                  <span style="font-size: 10px; color: ', @CpuSqlColor, '; font-weight: bold;">&#9679; ', @CpuSqlStatus, '</span>
                </td>
                <td width="33.33%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px; vertical-align: top;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">CPU SO</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CASE WHEN @CpuSo IS NULL THEN 'N/D' ELSE CONCAT(@CpuSo, '%') END, '</span><br>
                  <span style="font-size: 10px; color: ', @CpuSoColor, '; font-weight: bold;">&#9679; ', @CpuSoStatus, '</span>
                </td>
                <td width="33.33%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px; vertical-align: top;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">PLE (seg)</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', ISNULL(CAST(@PLE AS VARCHAR(10)), 'N/D'), '</span><br>
                  <span style="font-size: 10px; color: ', CASE WHEN @PLE IS NULL THEN '#6c757d' WHEN @PLE < @PleWarning THEN '#b77900' ELSE '#28a745' END, '; font-weight: bold;">&#9679; ', CASE WHEN @PLE IS NULL THEN 'SIN DATOS' WHEN @PLE < @PleWarning THEN 'BAJO' ELSE 'NORMAL' END, '</span>
                </td>
              </tr>
              <!-- FILA 2 -->
              <tr>
                <td width="33.33%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px; vertical-align: top;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">MEMORIA SO</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CASE WHEN @OSMemPct IS NULL THEN 'N/D' ELSE CONCAT(@OSMemPct, '%') END, '</span><br>
                  <span style="font-size: 10px; color: #6c757d;">de RAM utilizada</span><br>
                  <span style="font-size: 11px; line-height: 17px; color: #495057;">En uso: <b>', ISNULL(CAST(@UsedOSGB AS VARCHAR(10)), 'N/D'), ' GiB</b></span><br>
                  <span style="font-size: 11px; line-height: 17px; color: #495057;">RAM total: <b>', ISNULL(CAST(@TotalOSGB AS VARCHAR(10)), 'N/D'), ' GiB</b></span><br>
                  <span style="font-size: 10px; color: ', CASE WHEN @OSMemPct IS NULL THEN '#6c757d' WHEN @OSMemPct > @MemoryWarning THEN '#dc3545' ELSE '#28a745' END, '; font-weight: bold;">&#9679; ', CASE WHEN @OSMemPct IS NULL THEN 'SIN DATOS' WHEN @OSMemPct > @MemoryWarning THEN 'ALERTA' ELSE 'NORMAL' END, '</span>
                </td>
                <td width="33.33%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px; vertical-align: top;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">MEMORIA SQL</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CASE WHEN @SQLMemPct IS NULL THEN N'N/D' ELSE CONCAT(@SQLMemPct, N'%') END, '</span><br>
                  <span style="font-size: 10px; color: #6c757d;">', ISNULL(@SQLMemPctBasis,N'referencia no disponible'), '</span><br>
                  <span style="font-size: 11px; line-height: 17px; color: #495057;">En uso: <b>', CASE WHEN @SQLMemGB IS NULL THEN N'N/D' ELSE CONCAT(CAST(@SQLMemGB AS VARCHAR(10)), N' GiB') END, '</b></span><br>
                  <span style="font-size: 11px; line-height: 17px; color: #495057;">Límite SQL: <b>', ISNULL(@SQLMemLimitText,N'no disponible'), '</b></span><br>
                  <span style="font-size: 10px; color: ', @SQLMemStatusColor, '; font-weight: bold;">&#9679; ', @SQLMemStatus, '</span>
                </td>
                <td width="33.33%" align="center" valign="middle" style="background: #f1f3f5; border-radius: 4px; padding: 10px; vertical-align: middle;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">BLOQUEOS</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: ', CASE WHEN @BlockedSessionsCount > 0 THEN '#dc3545' ELSE '#343a40' END, ';">', ISNULL(CAST(@BlockedSessionsCount AS VARCHAR(5)), 'N/D'), '</span><br>
                  <span style="font-size: 10px; color: ', CASE WHEN @BlockedSessionsCount IS NULL THEN '#6c757d' WHEN @BlockedSessionsCount > 0 THEN '#dc3545' ELSE '#28a745' END, '; font-weight: bold;">&#9679; ', CASE WHEN @BlockedSessionsCount IS NULL THEN 'SIN DATOS' WHEN @BlockedSessionsCount > 0 THEN 'ALERTA' ELSE 'SIN BLOQUEOS' END, '</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>'
);

-- HTML PARTE 2: UNIDADES COMPACTAS TIPO EXPLORADOR, DOS POR FILA
SET @Html = @Html + N'
        <tr>
          <td style="padding: 10px 15px;">
            <span style="font-size: 13px; font-weight: bold; color: #1e3d59;">ESPACIO EN DISCOS (GiB - 1024&#179;)</span>
            <p style="margin: 5px 0; font-size: 10px; color: #6c757d;">Volúmenes de la instancia. La barra indica el espacio ocupado en todo el volumen.</p>
            <table id="disk-volumes" width="100%" cellpadding="0" cellspacing="0" border="0" style="table-layout: fixed;">';

DECLARE @RowID INT = 1, @MaxRow INT;
SELECT @MaxRow = ISNULL(MAX(RowID), 0) FROM #Disks;

IF @MaxRow = 0
    SET @Html = @Html + N'<tr><td colspan="2" style="padding: 10px; font-size: 11px; color: #6c757d;">SIN DATOS: no se obtuvieron volúmenes. Consulte la cobertura de consultas.</td></tr>';

WHILE @RowID <= @MaxRow
BEGIN
    DECLARE @Vol NVARCHAR(2048), @Tot DECIMAL(10,2), @Free DECIMAL(10,2), @Pct INT, @Stat VARCHAR(20);
    SELECT @Vol = VolumeName, @Tot = TotalGiB, @Free = FreeGiB, @Pct = UsedPct, @Stat = DiskStatus
    FROM #Disks WHERE RowID = @RowID;

    SET @Vol = REPLACE(REPLACE(REPLACE(@Vol, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
    IF @RowID % 2 = 1
        SET @Html = @Html + N'<tr>';

    SET @Html = @Html + CONCAT(CAST(N'' AS NVARCHAR(MAX)), N'
                <td class="disk-volume" width="50%" valign="top" style="padding: 8px;">
                  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="table-layout: fixed;">
                    <tr>
                      <!-- Icono de unidad en HTML, sin imagenes externas. -->
                      <td width="42" valign="middle" style="padding-right: 8px;">
                        <table role="presentation" aria-hidden="true" width="34" cellpadding="0" cellspacing="0" border="0" style="table-layout: fixed;">
                          <tr><td height="8" style="background: #d4d9df; border: 1px solid #b7bec7; font-size: 0; line-height: 8px;">&nbsp;</td></tr>
                          <tr><td height="12" style="background: #4b5563; border: 1px solid #374151; padding-left: 4px; font-size: 9px; line-height: 12px; color: #72d572;">&#9679;</td></tr>
                        </table>
                      </td>
                      <td valign="top">
                        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="table-layout: fixed;">
                          <tr>
                            <td style="font-size: 12px; font-weight: bold; color: #1e3d59; word-wrap: break-word;">', @Vol, N'</td>
                            <td width="48" align="right" style="font-size: 9px; color: ', CASE WHEN @Stat = 'CRITICO' THEN '#dc3545' ELSE '#6c757d' END, N';">', @Stat, N'</td>
                          </tr>
                          <tr>
                            <td colspan="2" style="padding-top: 4px;">
                              <table class="disk-usage" width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #e6e6e6; border: 1px solid #bcbcbc; table-layout: fixed; height: 10px;">
                                <tr>');

    -- Omitir celdas de ancho cero para representar también 0% y 100% de uso.
    IF @Pct > 0
        SET @Html = @Html + CONCAT(N'<td width="', CAST(@Pct AS VARCHAR(3)), N'%" height="10" style="background: ', CASE WHEN @Stat = 'CRITICO' THEN '#c42b1c' ELSE '#0078d4' END, N'; font-size: 0; line-height: 10px;">&nbsp;</td>');
    IF @Pct < 100
        SET @Html = @Html + CONCAT(N'<td width="', CAST(100 - @Pct AS VARCHAR(3)), N'%" height="10" style="background: #e6e6e6; font-size: 0; line-height: 10px;">&nbsp;</td>');

    SET @Html = @Html + CONCAT(N'
                                </tr>
                              </table>
                            </td>
                          </tr>
                          <tr>
                            <td colspan="2" style="padding-top: 4px; font-size: 10px; line-height: 14px; color: #495057;">', CAST(@Free AS VARCHAR(10)), N' GiB libres de ', CAST(@Tot AS VARCHAR(10)), N' GiB</td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                  </table>
                </td>');

    -- La ultima unidad conserva medio ancho incluso cuando queda sola.
    IF @RowID = @MaxRow AND @RowID % 2 = 1
        SET @Html = @Html + N'<td width="50%" style="padding: 8px;"></td>';
    IF @RowID % 2 = 0 OR @RowID = @MaxRow
        SET @Html = @Html + N'</tr>';

    SET @RowID = @RowID + 1;
END;

SET @Html = @Html + N'</table></td></tr>';

-- HTML: estado de bases, TEMPDB y LOG. Los valores se serializan como texto XML
-- para escapar nombres y mensajes antes de insertarlos en las tablas HTML.
DECLARE @SectionRows NVARCHAR(MAX),@SectionBody NVARCHAR(MAX),@SectionTitle NVARCHAR(200),@SectionNote NVARCHAR(MAX);
IF OBJECT_ID('tempdb..#HealthSections') IS NOT NULL DROP TABLE #HealthSections;
CREATE TABLE #HealthSections(SortOrder INT,Title NVARCHAR(200),Note NVARCHAR(MAX),Body NVARCHAR(MAX));
SET @SectionRows=CONVERT(NVARCHAR(MAX),(SELECT DatabaseName AS [td],N'',StateDesc AS [td],N'',RecoveryModel AS [td],N'',
    CASE WHEN Exclusion IS NOT NULL THEN CONCAT(N'EXCLUIDA: ',Exclusion) WHEN StateDesc=N'ONLINE' THEN N'NORMAL' ELSE N'REVISAR' END AS [td]
    FROM #DatabaseHealth ORDER BY CASE WHEN StateDesc=N'ONLINE' THEN 1 ELSE 0 END,DatabaseName FOR XML PATH('tr'),TYPE));
INSERT #HealthSections VALUES(1,N'ESTADO DE LAS BASES - ACTUAL',N'Las excepciones de mantenimiento se muestran pero no penalizan el puntaje.',
    CASE WHEN NOT EXISTS(SELECT 1 FROM #DatabaseHealth) THEN N'<p>SIN DATOS. Consulte la cobertura de consultas.</p>' ELSE CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<table width="100%" cellpadding="4" cellspacing="0" border="0" style="table-layout:fixed;"><tr bgcolor="#e9ecef"><th align="left">Base</th><th align="left">Estado</th><th align="left">Recuperación</th><th align="left">Evaluación</th></tr>',@SectionRows,N'</table>') END);
SET @SectionRows=CONVERT(NVARCHAR(MAX),(SELECT CONVERT(NVARCHAR(30),TotalMB) AS [td],N'',CONVERT(NVARCHAR(30),UsedMB) AS [td],N'',CONVERT(NVARCHAR(30),FreeMB) AS [td],N'',CONVERT(NVARCHAR(30),VersionMB) AS [td],N'',CONCAT(UsedPct,N'%') AS [td] FROM #TempdbSpace FOR XML PATH('tr'),TYPE));
INSERT #HealthSections VALUES(2,N'TEMPDB - ESPACIO ACTUAL',N'Espacio de los archivos de datos temporales, en MiB. Las versiones de filas son copias temporales de datos que SQL Server conserva para ciertas lecturas; su consumo ya está incluido en Usado. El archivo LOG de tempdb se muestra abajo.',
    CASE WHEN NOT EXISTS(SELECT 1 FROM #MonitorChecks WHERE CheckName=N'TEMPDB' AND ReadOK=1) THEN N'<p>SIN DATOS. Consulte la cobertura de consultas.</p>' ELSE CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<table width="100%" cellpadding="6" cellspacing="0" border="0" style="table-layout:fixed;"><tr bgcolor="#e9ecef"><th width="20%" align="center">Total MiB</th><th width="20%" align="center">Usado MiB</th><th width="20%" align="center">Libre MiB</th><th width="20%" align="center">Versiones de filas<br>MiB</th><th width="20%" align="center">Uso</th></tr>',@SectionRows,N'</table>') END);
SET @SectionRows=CONVERT(NVARCHAR(MAX),(SELECT DatabaseName AS [td],N'',ISNULL(CONVERT(NVARCHAR(30),TotalMB),N'N/D') AS [td],N'',ISNULL(CONVERT(NVARCHAR(30),UsedMB),N'N/D') AS [td],N'',ISNULL(CONVERT(NVARCHAR(30),FreeMB),N'N/D') AS [td],N'',
    CASE WHEN UsedPct IS NULL THEN N'N/D' ELSE CONCAT(UsedPct,N'%') END AS [td],N'',
    CASE WHEN ReadOK=1 THEN CONCAT(CASE WHEN UsedPct>=@SpaceCritical THEN N'CRITICO' WHEN UsedPct>=@SpaceWarning THEN N'ALERTA' ELSE N'NORMAL' END,N' / ',ReuseWait) ELSE CONCAT(CASE WHEN ReadOK=0 THEN N'SIN DATOS: ' ELSE N'' END,Details) END AS [td]
    FROM #DatabaseLog ORDER BY CASE WHEN UsedPct>=@SpaceWarning THEN 0 ELSE 1 END,DatabaseName FOR XML PATH('tr'),TYPE));
INSERT #HealthSections VALUES(3,N'LOG DE TRANSACCIONES (LDF) - ESPACIO ACTUAL',N'Capacidad utilizable del log de transacciones, normalmente en archivos .ldf. Usado y libre son espacio dentro del log, no del disco. Si hay varios archivos de log, se agrupan por base. La causa de reutilización se interpreta junto con el porcentaje ocupado.',
    CASE WHEN NOT EXISTS(SELECT 1 FROM #DatabaseLog) THEN N'<p>SIN DATOS. Consulte la cobertura de consultas.</p>' ELSE CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<table width="100%" cellpadding="6" cellspacing="0" border="0" style="table-layout:fixed;"><tr bgcolor="#e9ecef"><th width="18%" align="center">Base</th><th width="14%" align="center">Total MiB</th><th width="14%" align="center">Usado MiB</th><th width="14%" align="center">Libre MiB</th><th width="12%" align="center">Uso</th><th width="28%" align="center">Estado / Reutilización</th></tr>',@SectionRows,N'</table>') END);
SET @SectionRows=CONVERT(NVARCHAR(MAX),(SELECT CONVERT(NVARCHAR(19),LogDate,120) AS [td],N'',ISNULL(CONVERT(NVARCHAR(12),ErrorNumber),N'Aserción') AS [td],N'',ISNULL(CONVERT(NVARCHAR(12),Severity),N'N/D') AS [td],N'',Message AS [td] FROM #CriticalErrorLog ORDER BY LogDate DESC FOR XML PATH('tr'),TYPE));
INSERT #HealthSections VALUES(4,N'ERROR LOG - ERRORES RELEVANTES EN 24H',N'Cabeceras con severidad 20 o superior; errores 823/824/825, 701/802, 9002, 1101/1105 y aserciones de SQL Server. No se cuenta una línea solo por contener la palabra error. Se revisan archivos activos y archivados disponibles.',
    CASE WHEN @CriticalErrorsCount>0 THEN CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<table width="100%" cellpadding="4" cellspacing="0" border="0"><tr bgcolor="#e9ecef"><th>Fecha</th><th>Error</th><th>Severidad</th><th>Cabecera</th></tr>',@SectionRows,N'</table>')
    WHEN @ErrorLogRead=0 THEN N'<p>SIN DATOS COMPLETOS. No se pudo revisar todo el historial disponible.</p>' ELSE N'<p>Sin errores relevantes registrados en el historial disponible de las últimas 24 horas.</p>' END);
DECLARE healthSectionCursor CURSOR LOCAL FAST_FORWARD FOR SELECT Title,Note,Body FROM #HealthSections ORDER BY SortOrder;
OPEN healthSectionCursor;
FETCH NEXT FROM healthSectionCursor INTO @SectionTitle,@SectionNote,@SectionBody;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @SectionBody=REPLACE(REPLACE(@SectionBody,N'<td />',N'<td></td>'),N'<td/>',N'<td></td>');
    IF @SectionTitle IN(N'TEMPDB - ESPACIO ACTUAL',N'LOG DE TRANSACCIONES (LDF) - ESPACIO ACTUAL')
        SET @SectionBody=REPLACE(@SectionBody,N'<td>',N'<td align="center" valign="middle" style="text-align: center; vertical-align: middle; padding: 6px; word-wrap: break-word; border: 1px solid #e9ecef;">');
    ELSE
        SET @SectionBody=REPLACE(@SectionBody,N'<td>',N'<td valign="top" style="word-wrap: break-word; border-bottom: 1px solid #e9ecef;">');
    SET @Html=@Html+CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<tr><td style="padding: 10px 15px;"><table width="100%" cellpadding="10" cellspacing="0" border="0" style="background: #f8f9fa; table-layout: fixed;"><tr><td><b style="font-size: 12px; color: #1e3d59;">',@SectionTitle,N'</b><p style="font-size: 10px; color: #6c757d; margin: 5px 0;">',@SectionNote,N'</p><div style="font-size: 10px; color: #495057;">',@SectionBody,N'</div></td></tr></table></td></tr>');
    FETCH NEXT FROM healthSectionCursor INTO @SectionTitle,@SectionNote,@SectionBody;
END;
CLOSE healthSectionCursor; DEALLOCATE healthSectionCursor;


-- HTML PARTE 3: TRANSACCIONES, BLOQUEOS, JOBS, CONSULTAS Y RESUMEN
SET @Html = @Html + '
        <!-- TRANSACCIONES ABIERTAS -->
        <tr>
          <td style="padding: 10px 15px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f8f9fa; padding: 10px; border-radius: 4px;">
              <tr>
                <td>
                  <span style="font-size: 12px; font-weight: bold; color: #1e3d59;">TRANSACCIONES ABIERTAS</span>';

IF @ActiveTransCount > 0
BEGIN
    SET @Html = @Html + '<table width="100%" cellpadding="4" cellspacing="0" border="0" style="margin-top: 8px; font-size: 11px;">
      <tr style="background: #e9ecef; color: #495057;">
        <th align="left">SPID</th>
        <th align="left">Base de Datos</th>
        <th align="left">Usuario</th>
        <th align="left">Duración (seg)</th>
      </tr>';
    
    DECLARE @TSpid INT, @TDb NVARCHAR(128), @TUser NVARCHAR(128), @TSec INT;
    DECLARE curTrans CURSOR FOR SELECT SessionID, DatabaseName, LoginName, TransactionDurationSec FROM #ActiveTransList;
    OPEN curTrans;
    FETCH NEXT FROM curTrans INTO @TSpid, @TDb, @TUser, @TSec;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Html = @Html + CONCAT('<tr style="border-bottom: 1px solid #dee2e6;">
          <td>', CAST(@TSpid AS VARCHAR(5)), '</td>
          <td><b>', @TDb, '</b></td>
          <td>', @TUser, '</td>
          <td style="color: ', CASE WHEN @TSec>300 THEN '#dc3545' ELSE '#495057' END, '; font-weight: bold;">', CAST(@TSec AS VARCHAR(10)), ' seg</td>
        </tr>');
        FETCH NEXT FROM curTrans INTO @TSpid, @TDb, @TUser, @TSec;
    END
    CLOSE curTrans;
    DEALLOCATE curTrans;

    SET @Html = @Html + '</table>';
END
ELSE IF @ActiveTransCount IS NULL
    SET @Html=@Html+N'<p style="font-size:11px; color:#856404;">SIN DATOS: no se pudo consultar transacciones. Consulte la cobertura de consultas.</p>';
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">&#10004; No se observaron transacciones de otras sesiones de usuario al consultar.</p>';
END

SET @Html = @Html + '
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- SESIONES BLOQUEADAS -->
        <tr>
          <td style="padding: 10px 15px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f8f9fa; padding: 10px; border-radius: 4px;">
              <tr>
                <td>
                  <span style="font-size: 12px; font-weight: bold; color: #1e3d59;">SESIONES BLOQUEADAS</span>';

IF @BlockedSessionsCount > 0
BEGIN
    SET @Html = @Html + '<table width="100%" cellpadding="4" cellspacing="0" border="0" style="margin-top: 8px; font-size: 11px;">
      <tr style="background: #e9ecef; color: #495057;">
        <th align="left">Blocked SPID</th>
        <th align="left">Blocking SPID</th>
        <th align="left">Base de Datos</th>
        <th align="left">Espera (ms)</th>
      </tr>';
    
    DECLARE @BSpid INT, @BlkSpid INT, @B1Db NVARCHAR(128), @BWait INT;
    DECLARE curBlock CURSOR FOR SELECT BlockedSPID, BlockingSPID, DatabaseName, WaitTimeMs FROM #BlockedList;
    OPEN curBlock;
    FETCH NEXT FROM curBlock INTO @BSpid, @BlkSpid, @B1Db, @BWait;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Html = @Html + CONCAT('<tr style="border-bottom: 1px solid #dee2e6;">
          <td style="color: #dc3545; font-weight: bold;">', CAST(@BSpid AS VARCHAR(5)), '</td>
          <td style="color: #dc3545; font-weight: bold;">', CAST(@BlkSpid AS VARCHAR(5)), '</td>
          <td><b>', @B1Db, '</b></td>
          <td>', CAST(@BWait AS VARCHAR(10)), '</td>
        </tr>');
        FETCH NEXT FROM curBlock INTO @BSpid, @BlkSpid, @B1Db, @BWait;
    END
    CLOSE curBlock;
    DEALLOCATE curBlock;

    SET @Html = @Html + '</table>';
END
ELSE IF @BlockedSessionsCount IS NULL
    SET @Html=@Html+N'<p style="font-size:11px; color:#856404;">SIN DATOS: no se pudo consultar bloqueos. Consulte la cobertura de consultas.</p>';
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">&#10004; Instancia sin sesiones bloqueadas activas.</p>';
END

SET @Html = @Html + '
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- JOBS FALLIDOS -->
        <tr>
          <td style="padding: 10px 15px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f8f9fa; padding: 10px; border-radius: 4px;">
              <tr>
                <td>
                  <span style="font-size: 12px; font-weight: bold; color: #1e3d59;">SQL AGENT JOBS FALLIDOS (ÚLTIMAS 24H)</span>';

IF @FailedJobsCount > 0
BEGIN
    SET @Html = @Html + '<table width="100%" cellpadding="4" cellspacing="0" border="0" style="margin-top: 8px; font-size: 11px;">
      <tr style="background: #e9ecef; color: #495057;">
        <th align="left">Job Name</th>
        <th align="left">Última Ejecución (Fallo)</th>
        <th align="left">Mensaje de Error</th>
      </tr>';
    
    DECLARE @JName SYSNAME, @JDate VARCHAR(30), @JMsg NVARCHAR(MAX);
    DECLARE curJobs CURSOR FOR
        SELECT JobName, CONVERT(VARCHAR(19), RunDateTime, 120), Message
        FROM #FailedJobs
        ORDER BY RunDateTime DESC, JobName;
    OPEN curJobs;
    FETCH NEXT FROM curJobs INTO @JName, @JDate, @JMsg;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Html = @Html + CONCAT('<tr style="border-bottom: 1px solid #dee2e6;">
          <td style="color: #dc3545; font-weight: bold;">', @JName, '</td>
          <td style="color: #6c757d; white-space: nowrap;">', @JDate, '</td>
          <td style="color: #495057; font-size: 10px;">', LEFT(@JMsg, 80), '</td>
        </tr>');
        FETCH NEXT FROM curJobs INTO @JName, @JDate, @JMsg;
    END
    CLOSE curJobs;
    DEALLOCATE curJobs;

    SET @Html = @Html + '</table>';
END
ELSE IF @FailedJobsCount IS NULL
    SET @Html=@Html+N'<p style="font-size:11px; color:#856404;">SIN DATOS: no se pudo consultar jobs. Consulte la cobertura de consultas.</p>';
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">&#10004; No se registraron ejecuciones de jobs fallidas en el historial disponible de las últimas 24 horas.</p>';
END

SET @Html = @Html + '
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- INTEGRATION SERVICES: FALLOS Y ERRORES DEL CATALOGO SSISDB -->
        <tr>
          <td style="padding: 10px 15px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f8f9fa; padding: 10px; border-radius: 4px;">
              <tr>
                <td>
                  <span style="font-size: 12px; font-weight: bold; color: #1e3d59;">INTEGRATION SERVICES (DTSX) - FALLOS EN LAS ÚLTIMAS 24H</span>';

SET @Html = @Html + N'<p style="margin: 5px 0; font-size: 10px; color: #6c757d;">Paquetes fallidos o finalizados inesperadamente en SSISDB. Fechas en la hora del servidor; ventana calculada al finalizar la ejecución.</p>';

IF @FailedSsisCount > 0
BEGIN
    SET @Html = @Html + N'<table id="failed-ssis" width="100%" cellpadding="4" cellspacing="0" border="0" style="margin-top: 8px; font-size: 11px; table-layout: fixed;">
      <tr style="background: #e9ecef; color: #495057;">
        <th width="30%" align="left">Proyecto / Paquete</th>
        <th width="24%" align="left">Fecha y hora</th>
        <th width="46%" align="left">Error del paquete</th>
      </tr>';

    DECLARE @SsisID VARCHAR(20), @SsisContext NVARCHAR(MAX), @SsisPackage NVARCHAR(MAX), @SsisErrorPackage NVARCHAR(MAX), @SsisSource NVARCHAR(MAX),
        @SsisStart VARCHAR(19), @SsisFailure VARCHAR(19), @SsisStatus INT, @SsisMessage NVARCHAR(MAX);
    DECLARE curSsis CURSOR LOCAL FAST_FORWARD FOR
        SELECT CAST(ExecutionID AS VARCHAR(20)), CONCAT(FolderName, N' / ', ProjectName), PackageName,
            ISNULL(ErrorPackage, N''), ISNULL(ErrorSource, N''),
            CONVERT(VARCHAR(19), SWITCHOFFSET(StartDateTime, DATENAME(TZOFFSET, @SsisWindowEnd)), 120),
            CONVERT(VARCHAR(19), SWITCHOFFSET(FailureDateTime, DATENAME(TZOFFSET, @SsisWindowEnd)), 120),
            ExecutionStatus, Message
        FROM #FailedSsis
        ORDER BY FailureDateTime DESC, ExecutionID DESC;
    OPEN curSsis;
    FETCH NEXT FROM curSsis INTO @SsisID, @SsisContext, @SsisPackage, @SsisErrorPackage, @SsisSource, @SsisStart, @SsisFailure, @SsisStatus, @SsisMessage;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Escapar los nombres y el error completo sin perder saltos de linea.
        SELECT
            @SsisContext = REPLACE(REPLACE(REPLACE(@SsisContext, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
            @SsisPackage = REPLACE(REPLACE(REPLACE(@SsisPackage, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
            @SsisErrorPackage = REPLACE(REPLACE(REPLACE(@SsisErrorPackage, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
            @SsisSource = REPLACE(REPLACE(REPLACE(@SsisSource, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
            @SsisMessage = REPLACE(REPLACE(REPLACE(@SsisMessage, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
        SET @SsisMessage = REPLACE(REPLACE(REPLACE(@SsisMessage, CHAR(13) + CHAR(10), CHAR(10)), CHAR(13), CHAR(10)), CHAR(10), N'<br>');
        SET @Html = @Html + CONCAT(CAST(N'' AS NVARCHAR(MAX)), N'<tr>
          <td valign="top" style="word-wrap: break-word;"><b style="color: #dc3545;">', @SsisPackage, N'</b><br><span style="font-size: 10px; color: #6c757d;">', @SsisContext, N'<br>ID: ', @SsisID, N'<br>', CASE WHEN @SsisStatus = 6 THEN N'Finalización inesperada' ELSE N'Fallido' END, N'</span></td>
          <td valign="top" style="font-size: 10px; color: #6c757d;">Inicio:<br>', ISNULL(@SsisStart, 'No registrado'), N'<br>Fallo:<br>', @SsisFailure, N'</td>
          <td valign="top" style="font-size: 10px; color: #495057; word-wrap: break-word;">',
            CASE WHEN @SsisErrorPackage <> N'' THEN CONCAT(N'<b>Paquete del error:</b> ', @SsisErrorPackage, N'<br>') ELSE N'' END,
            CASE WHEN @SsisSource <> N'' THEN CONCAT(N'<b>Origen:</b> ', @SsisSource, N'<br>') ELSE N'' END,
            @SsisMessage, N'</td>
        </tr>');
        FETCH NEXT FROM curSsis INTO @SsisID, @SsisContext, @SsisPackage, @SsisErrorPackage, @SsisSource, @SsisStart, @SsisFailure, @SsisStatus, @SsisMessage;
    END;
    CLOSE curSsis;
    DEALLOCATE curSsis;
    SET @Html = @Html + N'</table>';
END
ELSE IF @SsisCatalogRead = 0
BEGIN
    SET @SsisNotice = REPLACE(REPLACE(REPLACE(@SsisNotice, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
    SET @Html = @Html + CONCAT(CAST(N'' AS NVARCHAR(MAX)), N'<p style="margin: 5px 0 0; font-size: 11px; color: #856404;">', @SsisNotice, N'</p>');
END
ELSE
    SET @Html = @Html + N'<p style="margin: 5px 0 0; font-size: 11px; color: #28a745; font-weight: bold;">&#10004; No se registraron ejecuciones SSIS fallidas visibles para esta cuenta en las últimas 24 horas.</p>';

SET @Html = @Html + N'<p style="margin: 5px 0 0; font-size: 10px; color: #6c757d;">Se muestra el primer error de cada ejecución. El ID permite consultar los demás mensajes en SSISDB. La visibilidad depende de los permisos y del historial conservado en el catálogo.</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- CONSULTAS DE LARGA DURACIÓN -->
        <tr>
          <td style="padding: 10px 15px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f8f9fa; padding: 10px; border-radius: 4px;">
              <tr>
                <td>
                  <span style="font-size: 12px; font-weight: bold; color: #1e3d59;">CONSULTAS DE LARGA DURACIÓN (> 5 MIN)</span>';

IF @LongQueriesCount > 0
BEGIN
    SET @Html = @Html + '<table width="100%" cellpadding="4" cellspacing="0" border="0" style="margin-top: 8px; font-size: 11px;">
      <tr style="background: #e9ecef; color: #495057;">
        <th align="left">SPID</th>
        <th align="left">Base de Datos</th>
        <th align="left">Usuario</th>
        <th align="left">Minutos</th>
      </tr>';
    
    DECLARE @LQSpid INT, @LQDb NVARCHAR(128), @LUser NVARCHAR(128), @LMin INT;
    DECLARE curQ CURSOR FOR SELECT SessionID, DatabaseName, LoginName, ElapsedMinutes FROM #LongQueries;
    OPEN curQ;
    FETCH NEXT FROM curQ INTO @LQSpid, @LQDb, @LUser, @LMin;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Html = @Html + CONCAT('<tr style="border-bottom: 1px solid #dee2e6;">
          <td>', CAST(@LQSpid AS VARCHAR(5)), '</td>
          <td><b>', @LQDb, '</b></td>
          <td>', @LUser, '</td>
          <td style="color: #dc3545; font-weight: bold;">', CAST(@LMin AS VARCHAR(5)), ' min</td>
        </tr>');
        FETCH NEXT FROM curQ INTO @LQSpid, @LQDb, @LUser, @LMin;
    END
    CLOSE curQ;
    DEALLOCATE curQ;

    SET @Html = @Html + '</table>';
END
ELSE IF @LongQueriesCount IS NULL
    SET @Html=@Html+N'<p style="font-size:11px; color:#856404;">SIN DATOS: no se pudo consultar consultas largas. Consulte la cobertura de consultas.</p>';
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">&#10004; No hay consultas ejecutándose por más de 5 minutos en ninguna base de datos.</p>';
END

SET @Html=@Html+N'</td></tr></table></td></tr>';
DECLARE @AlertRows NVARCHAR(MAX)=CONVERT(NVARCHAR(MAX),(SELECT Area AS [td],N'',Penalty AS [td],N'',Detail AS [td] FROM #MonitorAlerts ORDER BY Penalty DESC,Area FOR XML PATH('tr'),TYPE));
DECLARE @CoverageRows NVARCHAR(MAX)=CONVERT(NVARCHAR(MAX),(SELECT CheckName AS [td],N'',CASE WHEN ReadOK=1 THEN N'CONSULTADO' WHEN ReadOK=0 THEN N'SIN DATOS COMPLETOS' ELSE N'NO APLICA' END AS [td],N'',
    CONVERT(NVARCHAR(19),CollectedAt,120) AS [td],N'',CASE WHEN ReadOK=0 AND ISNULL(Details,N'')=N'' THEN N'No se obtuvieron datos válidos o la muestra está desactualizada.' WHEN ReadOK=1 THEN N'' ELSE ISNULL(Details,N'') END AS [td]
    FROM #MonitorChecks ORDER BY CASE WHEN ReadOK=0 THEN 0 ELSE 1 END,CheckName FOR XML PATH('tr'),TYPE));
SET @CoverageRows=REPLACE(REPLACE(REPLACE(@CoverageRows,N'<td />',N'<td></td>'),N'<td/>',N'<td></td>'),N'<td>',N'<td valign="top" style="word-wrap:break-word;">');
SET @Html=@Html+CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<tr><td style="padding:10px 15px;"><table width="100%" cellpadding="10" cellspacing="0" style="background:#f8f9fa;"><tr><td><b style="font-size:12px;color:#1e3d59;">HALLAZGOS Y PUNTAJE</b><p style="font-size:11px;">',
    CASE WHEN @MissingChecks>0 THEN N'Evaluación incompleta: el puntaje no está disponible. Revise los controles sin datos.' ELSE CONCAT(N'Puntaje: ',@HealthScore,N'/100. Las filas siguientes explican cada descuento.') END,N'</p>',
    CASE WHEN EXISTS(SELECT 1 FROM #MonitorAlerts) THEN CONCAT(CAST(N'' AS NVARCHAR(MAX)),N'<table width="100%" cellpadding="4" cellspacing="0" style="font-size:10px;"><tr bgcolor="#e9ecef"><th>Área</th><th>Descuento</th><th>Hallazgo</th></tr>',@AlertRows,N'</table>') ELSE N'<p style="font-size:11px;">Sin alertas en los controles que pudieron consultarse.</p>' END,
    N'<p style="font-size:10px;color:#6c757d;">Umbrales: CPU alerta ',@CpuWarning,N'%, crítica ',@CpuCritical,N'%; RAM SO &gt; ',@MemoryWarning,N'%; PLE &lt; ',@PleWarning,N' s (referencia configurable); TEMPDB/LOG alerta ',@SpaceWarning,N'%, crítico ',@SpaceCritical,N'%. Un valor aislado no equivale a un diagnóstico.</p></td></tr></table></td></tr>
    <tr><td style="padding:10px 15px 20px;"><b style="font-size:12px;color:#1e3d59;">COBERTURA DE CONSULTAS</b><p style="font-size:10px;color:#6c757d;">CONSULTADO indica acceso y lectura; no significa ausencia de alertas. SIN DATOS no equivale a cero problemas. Los historiales dependen de retención y permisos.</p><table width="100%" cellpadding="4" cellspacing="0" style="font-size:10px;table-layout:fixed;"><tr bgcolor="#e9ecef"><th>Control</th><th>Cobertura</th><th>Consulta</th><th>Detalle</th></tr>',@CoverageRows,N'</table></td></tr>');

-- CIERRE FINAL DEL CONTENEDOR MAESTRO
SET @Html = @Html + '
      </table>
    </td>
  </tr>
</table>
</body>
</html>';

SELECT @Html AS ReporteHTML;
