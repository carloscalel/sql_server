--------------------------------------------------------------------------------
-- SCRIPT CORREGIDO Y COMPLETO: MONITOREO OPERATIVO SQL SERVER
-- Mejoras:
-- 1. Tarjetas y sección dedicada y prominente para Memoria SO y Memoria SQL Server.
-- 2. Tablas detalladas para Transacciones Abiertas y Sesiones Bloqueadas.
-- 3. Extracción correcta de Base de Datos y Usuario real por sesión.
-- 4. Codificación limpia en HTML (sin símbolos corruptos o '?').
--------------------------------------------------------------------------------

USE msdb;
GO

SET NOCOUNT ON;

DECLARE @ServerName NVARCHAR(128) = ISNULL(@@SERVERNAME, 'N/A');
DECLARE @InstanceName NVARCHAR(128) = ISNULL(@@SERVICENAME, 'N/A');
DECLARE @SQLVersion NVARCHAR(128) = ISNULL(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) + ' - ' + CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)), 'N/A');
DECLARE @ReportDate NVARCHAR(50) = ISNULL(CONVERT(NVARCHAR(30), GETDATE(), 120), '');

-- 1. Captura de CPU (SQL vs SO) usando sys.dm_os_ring_buffers
DECLARE @CpuSql INT = 0, @CpuSo INT = 0;
SELECT TOP 1 
    @CpuSql = ISNULL(Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int'), 0),
    @CpuSo = 100 - ISNULL(Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'), 100)
FROM (
    SELECT CAST(record AS XML) AS Record 
    FROM sys.dm_os_ring_buffers 
    WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
      AND record LIKE '%SystemHealth%'
) x
ORDER BY 1 DESC;

-- 2. Page Life Expectancy (PLE)
DECLARE @PLE INT = 0;
SELECT @PLE = ISNULL(cntr_value, 0) 
FROM sys.dm_os_performance_counters 
WHERE counter_name = N'Page life expectancy' 
  AND object_name LIKE N'%Buffer Manager%';

-- 3. Memoria SO
DECLARE @TotalOSGB DECIMAL(10,2) = 0, @FreeOSGB DECIMAL(10,2) = 0, @UsedOSGB DECIMAL(10,2) = 0, @OSMemPct INT = 0;
SELECT 
    @TotalOSGB = ISNULL(CAST(total_physical_memory_kb / 1024.0 / 1024.0 AS DECIMAL(10,2)), 1),
    @FreeOSGB = ISNULL(CAST(available_physical_memory_kb / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    @UsedOSGB = ISNULL(CAST((total_physical_memory_kb - available_physical_memory_kb) / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    @OSMemPct = ISNULL(100 - CAST((CAST(available_physical_memory_kb AS FLOAT) / NULLIF(total_physical_memory_kb, 0) * 100) AS INT), 0)
FROM sys.dm_os_sys_memory;

-- 4. Memoria SQL Server
DECLARE @SQLMemGB DECIMAL(10,2) = 0, @SQLTargetMemGB DECIMAL(10,2) = 0;
SELECT 
    @SQLMemGB = ISNULL(CAST(MAX(CASE WHEN counter_name LIKE N'Total Server Memory (KB%' THEN cntr_value END) / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0),
    @SQLTargetMemGB = ISNULL(CAST(MAX(CASE WHEN counter_name LIKE N'Target Server Memory (KB%' THEN cntr_value END) / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0)
FROM sys.dm_os_performance_counters 
WHERE object_name LIKE N'%Memory Manager%';

-- 5. Transacciones Abiertas (Detalle corregido por sesión y base de datos real)
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
LEFT JOIN sys.dm_tran_database_transactions dt ON t.transaction_id = dt.transaction_id;

DECLARE @ActiveTransCount INT;
SELECT @ActiveTransCount = COUNT(1) FROM #ActiveTransList;

-- 6. Bloqueos y Sesiones Bloqueadas (Conteo y Detalle)
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

-- 7. SQL Agent Jobs Fallidos (Últimas 24 horas)
IF OBJECT_ID('tempdb..#FailedJobs') IS NOT NULL DROP TABLE #FailedJobs;
CREATE TABLE #FailedJobs (
    JobName SYSNAME,
    RunDateTime VARCHAR(30),
    Message NVARCHAR(MAX)
);

INSERT INTO #FailedJobs (JobName, RunDateTime, Message)
SELECT 
    ISNULL(j.name, 'Desconocido'),
    ISNULL(STUFF(STUFF(STUFF(CAST(h.run_date AS CHAR(8)), 5, 0, '-'), 8, 0, '-'), 11, 0, ' ') + ' ' +
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':'), ''),
    ISNULL(h.message, '')
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE h.run_status = 0 
  AND h.step_id = 0 
  AND CAST(CAST(h.run_date AS CHAR(8)) AS DATETIME) >= DATEADD(DAY, -1, GETDATE());

DECLARE @FailedJobsCount INT;
SELECT @FailedJobsCount = ISNULL(COUNT(1), 0) FROM #FailedJobs;

-- 8. Errores Críticos en el Error Log
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;
CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo VARCHAR(50),
    Text NVARCHAR(MAX)
);

BEGIN TRY
    INSERT INTO #ErrorLog
    EXEC sp_readerrorlog 0, 1, NULL, NULL, NULL, NULL, N'desc';
END TRY
BEGIN CATCH
END CATCH

DECLARE @CriticalErrorsCount INT = 0;
SELECT @CriticalErrorsCount = ISNULL(COUNT(1), 0) 
FROM #ErrorLog 
WHERE LogDate >= DATEADD(DAY, -1, GETDATE())
  AND (Text LIKE '%error%' OR Text LIKE '%severe%' OR Text LIKE '%assertion%');

-- 9. Consultas de Larga Duración (> 5 minutos, excluyendo procesos de sistema inactivos)
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
  AND r.status <> 'background';

DECLARE @LongQueriesCount INT;
SELECT @LongQueriesCount = ISNULL(COUNT(1), 0) FROM #LongQueries;

-- 10. Puntuación de Salud Ponderada
DECLARE @HealthScore INT = 100;
IF @PLE < 300 SET @HealthScore = @HealthScore - 25;
IF @OSMemPct > 85 SET @HealthScore = @HealthScore - 20;
IF @BlockedSessionsCount > 0 SET @HealthScore = @HealthScore - (@BlockedSessionsCount * 10);
IF @FailedJobsCount > 0 SET @HealthScore = @HealthScore - (@FailedJobsCount * 15);
IF @CriticalErrorsCount > 0 SET @HealthScore = @HealthScore - 15;
IF @HealthScore < 0 SET @HealthScore = 0;

DECLARE @StatusText VARCHAR(50) = 'ESTABLE';
DECLARE @StatusColor VARCHAR(20) = '#28a745';
IF @HealthScore < 80 AND @HealthScore >= 60 BEGIN SET @StatusText = 'REQUIERE ATENCION'; SET @StatusColor = '#ffc107'; END
IF @HealthScore < 60 BEGIN SET @StatusText = 'CRITICO'; SET @StatusColor = '#dc3545'; END

-- 11. Captura de Discos en GiB real (1024^3)
IF OBJECT_ID('tempdb..#Disks') IS NOT NULL DROP TABLE #Disks;
CREATE TABLE #Disks (
    RowID INT IDENTITY(1,1),
    VolumeName VARCHAR(100),
    FileType VARCHAR(50),
    TotalGiB DECIMAL(10,2),
    FreeGiB DECIMAL(10,2),
    UsedGiB DECIMAL(10,2),
    UsedPct INT,
    DiskStatus VARCHAR(20)
);

INSERT INTO #Disks (VolumeName, FileType, TotalGiB, FreeGiB, UsedGiB, UsedPct, DiskStatus)
SELECT DISTINCT 
    ISNULL(vs.volume_mount_point, 'N/A') AS VolumeName,
    CASE 
        WHEN mf.type = 0 THEN 'DATA'
        WHEN mf.type = 1 THEN 'LOG'
        WHEN DB_NAME(mf.database_id) = 'tempdb' THEN 'TEMPDB'
        WHEN DB_NAME(mf.database_id) IN ('master','model','msdb') THEN 'MASTER/SYSTEM'
        ELSE 'DATA'
    END AS FileType,
    ISNULL(CAST(vs.total_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0) AS TotalGiB,
    ISNULL(CAST(vs.available_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0) AS FreeGiB,
    ISNULL(CAST((vs.total_bytes - vs.available_bytes) / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)), 0) AS UsedGiB,
    ISNULL(CAST((vs.total_bytes - vs.available_bytes) * 100.0 / NULLIF(vs.total_bytes, 0) AS INT), 0) AS UsedPct,
    CASE WHEN (ISNULL(vs.available_bytes * 100.0 / NULLIF(vs.total_bytes, 0), 100)) < 15 THEN 'CRITICO' ELSE 'NORMAL' END AS DiskStatus
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs;

-- 12. Construcción del HTML
DECLARE @Html NVARCHAR(MAX) = N'';

SET @Html = CONCAT(
'<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Monitor Operativo SQL Server</title>
</head>
<body style="margin:0; padding:0; background-color:#f4f6f9; font-family: Arial, sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f6f9; padding: 20px;">
  <tr>
    <td align="center">
      <table width="700" cellpadding="0" cellspacing="0" border="0" style="background-color:#ffffff; border-radius: 6px; overflow:hidden; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">
        
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
                  <span style="font-size: 42px; font-weight: bold; color: ', @StatusColor, ';">', CAST(@HealthScore AS VARCHAR(3)), '</span><br>
                  <span style="font-size: 12px; font-weight: bold; color: ', @StatusColor, '; letter-spacing: 1px;">', @StatusText, '</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- METRIC CARDS ROW 1: CPU, PLE, BLOQUEOS -->
        <tr>
          <td style="padding: 15px 15px 5px 15px;">
            <table width="100%" cellpadding="5" cellspacing="0" border="0">
              <tr>
                <td width="25%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">CPU SQL</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CAST(@CpuSql AS VARCHAR(3)), '%</span><br>
                  <span style="font-size: 10px; color: #28a745; font-weight: bold;">&#9679; NORMAL</span>
                </td>
                <td width="25%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">CPU SO</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CAST(@CpuSo AS VARCHAR(3)), '%</span><br>
                  <span style="font-size: 10px; color: #28a745; font-weight: bold;">&#9679; NORMAL</span>
                </td>
                <td width="25%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">PLE (seg)</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CAST(@PLE AS VARCHAR(10)), '</span><br>
                  <span style="font-size: 10px; color: ', CASE WHEN @PLE < 300 THEN '#dc3545' ELSE '#28a745' END, '; font-weight: bold;">&#9679; ', CASE WHEN @PLE < 300 THEN 'BAJO' ELSE 'NORMAL' END, '</span>
                </td>
                <td width="25%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 10px;">
                  <span style="font-size: 11px; color: #6c757d; font-weight: bold;">BLOQUEOS</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: ', CASE WHEN @BlockedSessionsCount > 0 THEN '#dc3545' ELSE '#343a40' END, ';">', CAST(@BlockedSessionsCount AS VARCHAR(5)), '</span><br>
                  <span style="font-size: 10px; color: ', CASE WHEN @BlockedSessionsCount > 0 THEN '#dc3545' ELSE '#28a745' END, '; font-weight: bold;">&#9679; ', CASE WHEN @BlockedSessionsCount > 0 THEN 'ALERTA' ELSE 'SIN BLOQUEOS' END, '</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- METRIC CARDS ROW 2: MEMORIA SO & SQL SERVER (SECCIÓN DESTACADA) -->
        <tr>
          <td style="padding: 5px 15px 15px 15px;">
            <table width="100%" cellpadding="5" cellspacing="0" border="0">
              <tr>
                <td width="50%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 12px;">
                  <span style="font-size: 11px; color: #1e3d59; font-weight: bold;">MEMORIA SO (Usada / Total)</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CAST(@OSMemPct AS VARCHAR(3)), '%</span><br>
                  <span style="font-size: 11px; color: #495057;"><b>', CAST(@UsedOSGB AS VARCHAR(10)), ' GB</b> / ', CAST(@TotalOSGB AS VARCHAR(10)), ' GB (Libre: ', CAST(@FreeOSGB AS VARCHAR(10)), ' GB)</span>
                  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #e9ecef; height: 6px; border-radius: 3px; margin-top: 6px;">
                    <tr>
                      <td width="', CAST(@OSMemPct AS VARCHAR(3)), '%" style="background: ', CASE WHEN @OSMemPct > 85 THEN '#dc3545' ELSE '#ff9800' END, '; height: 6px; border-radius: 3px 0 0 3px;"></td>
                      <td width="', CAST(100 - @OSMemPct AS VARCHAR(3)), '%"></td>
                    </tr>
                  </table>
                </td>
                <td width="50%" align="center" style="background: #f1f3f5; border-radius: 4px; padding: 12px;">
                  <span style="font-size: 11px; color: #1e3d59; font-weight: bold;">MEMORIA SQL SERVER (Asignada)</span><br>
                  <span style="font-size: 18px; font-weight: bold; color: #343a40;">', CAST(@SQLMemGB AS VARCHAR(10)), ' GB</span><br>
                  <span style="font-size: 11px; color: #495057;">Target Memory: <b>', CAST(@SQLTargetMemGB AS VARCHAR(10)), ' GB</b></span>
                  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #e9ecef; height: 6px; border-radius: 3px; margin-top: 6px;">
                    <tr>
                      <td width="100%" style="background: #17a2b8; height: 6px; border-radius: 3px;"></td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- ESPACIO EN DISCOS (2 DISCOS POR FILA EN GiB) -->
        <tr>
          <td style="padding: 10px 20px;">
            <span style="font-size: 13px; font-weight: bold; color: #1e3d59;">ESPACIO EN DISCOS (GiB - 1024³)</span>
            <table width="100%" cellpadding="5" cellspacing="0" border="0" style="margin-top: 5px;">'
);

-- Bucle para armar los discos de 2 en 2
DECLARE @RowID INT = 1, @MaxRow INT;
SELECT @MaxRow = ISNULL(MAX(RowID), 0) FROM #Disks;

WHILE @RowID <= @MaxRow
BEGIN
    DECLARE @Vol1 VARCHAR(100), @Type1 VARCHAR(50), @Tot1 DECIMAL(10,2), @Free1 DECIMAL(10,2), @Used1 DECIMAL(10,2), @Pct1 INT, @Stat1 VARCHAR(20);
    DECLARE @Vol2 VARCHAR(100), @Type2 VARCHAR(50), @Tot2 DECIMAL(10,2), @Free2 DECIMAL(10,2), @Used2 DECIMAL(10,2), @Pct2 INT, @Stat2 VARCHAR(20);

    SELECT @Vol1 = VolumeName, @Type1 = FileType, @Tot1 = TotalGiB, @Free1 = FreeGiB, @Used1 = UsedGiB, @Pct1 = UsedPct, @Stat1 = DiskStatus 
    FROM #Disks WHERE RowID = @RowID;

    SET @Html = @Html + '  <tr>';
    SET @Html = @Html + CONCAT('    <td width="50%" style="background: #f8f9fa; padding: 8px; border-radius: 4px; vertical-align: top;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
        <tr>
          <td><span style="font-size: 11px; font-weight: bold; color: #343a40;">', @Vol1, '</span></td>
          <td align="right"><span style="font-size: 10px; font-weight: bold; color: ', CASE WHEN @Stat1 = 'CRITICO' THEN '#dc3545' ELSE '#28a745' END, ';">', @Stat1, '</span></td>
        </tr>
        <tr>
          <td colspan="2"><span style="font-size: 10px; color: #1e3d59; font-weight: bold;">Tipo: ', @Type1, '</span></td>
        </tr>
        <tr>
          <td colspan="2" style="font-size: 10px; color: #6c757d; padding-top: 3px;">Libre: ', CAST(@Free1 AS VARCHAR(10)), ' GiB de ', CAST(@Tot1 AS VARCHAR(10)), ' GiB (', CAST(100 - @Pct1 AS VARCHAR(3)), '%)</td>
        </tr>
        <tr>
          <td colspan="2">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #e9ecef; height: 6px; border-radius: 3px; margin-top: 4px;">
              <tr>
                <td width="', CAST(@Pct1 AS VARCHAR(3)), '%" style="background: ', CASE WHEN @Stat1 = 'CRITICO' THEN '#dc3545' ELSE '#17a2b8' END, '; height: 6px; border-radius: 3px 0 0 3px;"></td>
                <td width="', CAST(100 - @Pct1 AS VARCHAR(3)), '%"></td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </td>');

    SET @RowID = @RowID + 1;

    IF @RowID <= @MaxRow
    BEGIN
        SELECT @Vol2 = VolumeName, @Type2 = FileType, @Tot2 = TotalGiB, @Free2 = FreeGiB, @Used2 = UsedGiB, @Pct2 = UsedPct, @Stat2 = DiskStatus 
        FROM #Disks WHERE RowID = @RowID;

        SET @Html = @Html + CONCAT('    <td width="50%" style="background: #f8f9fa; padding: 8px; border-radius: 4px; vertical-align: top;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0">
            <tr>
              <td><span style="font-size: 11px; font-weight: bold; color: #343a40;">', @Vol2, '</span></td>
              <td align="right"><span style="font-size: 10px; font-weight: bold; color: ', CASE WHEN @Stat2 = 'CRITICO' THEN '#dc3545' ELSE '#28a745' END, ';">', @Stat2, '</span></td>
            </tr>
            <tr>
              <td colspan="2"><span style="font-size: 10px; color: #1e3d59; font-weight: bold;">Tipo: ', @Type2, '</span></td>
            </tr>
            <tr>
              <td colspan="2" style="font-size: 10px; color: #6c757d; padding-top: 3px;">Libre: ', CAST(@Free2 AS VARCHAR(10)), ' GiB de ', CAST(@Tot2 AS VARCHAR(10)), ' GiB (', CAST(100 - @Pct2 AS VARCHAR(3)), '%)</td>
            </tr>
            <tr>
              <td colspan="2">
                <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #e9ecef; height: 6px; border-radius: 3px; margin-top: 4px;">
                  <tr>
                    <td width="', CAST(@Pct2 AS VARCHAR(3)), '%" style="background: ', CASE WHEN @Stat2 = 'CRITICO' THEN '#dc3545' ELSE '#17a2b8' END, '; height: 6px; border-radius: 3px 0 0 3px;"></td>
                    <td width="', CAST(100 - @Pct2 AS VARCHAR(3)), '%"></td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </td>');
        SET @RowID = @RowID + 1;
    END
    ELSE
    BEGIN
        SET @Html = @Html + '    <td width="50%"></td>';
    END

    SET @Html = @Html + '  </tr>';
END;

SET @Html = @Html + '
            </table>
          </td>
        </tr>

        <!-- TRANSACCIONES ABIERTAS (TABLA DETALLADA) -->
        <tr>
          <td style="padding: 10px 20px;">
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
          <td style="color: #d9534f; font-weight: bold;">', CAST(@TSec AS VARCHAR(10)), ' seg</td>
        </tr>');
        FETCH NEXT FROM curTrans INTO @TSpid, @TDb, @TUser, @TSec;
    END
    CLOSE curTrans;
    DEALLOCATE curTrans;

    SET @Html = @Html + '</table>';
END
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">✔ No hay transacciones abiertas en la instancia.</p>';
END

SET @Html = @Html + '
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- SESIONES BLOQUEADAS (TABLA DETALLADA) -->
        <tr>
          <td style="padding: 10px 20px;">
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
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">✔ Instancia sin sesiones bloqueadas activas.</p>';
END

SET @Html = @Html + '
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- JOBS FALLIDOS -->
        <tr>
          <td style="padding: 10px 20px;">
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
    DECLARE curJobs CURSOR FOR SELECT JobName, RunDateTime, Message FROM #FailedJobs;
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
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">✔ Todos los jobs ejecutados en las últimas 24 horas finalizaron exitosamente.</p>';
END

SET @Html = @Html + '
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- CONSULTAS DE LARGA DURACIÓN -->
        <tr>
          <td style="padding: 10px 20px;">
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
ELSE
BEGIN
    SET @Html = @Html + '<p style="margin: 5px 0 0 0; font-size: 11px; color: #28a745; font-weight: bold;">✔ No hay consultas ejecutándose por más de 5 minutos en ninguna base de datos.</p>';
END

SET @Html = @Html + CONCAT('
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- HALLAZGOS Y RESUMEN -->
        <tr>
          <td style="padding: 10px 20px 20px 20px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f8f9fa; padding: 10px; border-radius: 4px;">
              <tr>
                <td>
                  <span style="font-size: 12px; font-weight: bold; color: #1e3d59;">HALLAZGOS PRINCIPALES Y RESUMEN OPERATIVO</span>
                  <ul style="margin: 5px 0 0 20px; padding: 0; font-size: 11px; color: #495057;">
                    ', CASE WHEN @BlockedSessionsCount > 0 THEN CONCAT('<li style="color: #dc3545; font-weight: bold;">Se detectaron <b>', CAST(@BlockedSessionsCount AS VARCHAR(5)), '</b> sesiones bloqueadas.</li>') ELSE '<li>Sin bloqueos activos detectados.</li>' END, '
                    ', CASE WHEN @FailedJobsCount > 0 THEN CONCAT('<li style="color: #dc3545; font-weight: bold;">Se registraron <b>', CAST(@FailedJobsCount AS VARCHAR(5)), '</b> jobs fallidos en las últimas 24h.</li>') ELSE '<li>Jobs del SQL Agent sin fallos recientes.</li>' END, '
                    ', CASE WHEN @CriticalErrorsCount > 0 THEN CONCAT('<li style="color: #dc3545; font-weight: bold;">Se registraron <b>', CAST(@CriticalErrorsCount AS VARCHAR(5)), '</b> errores críticos en el Error Log.</li>') ELSE '<li>Sin errores críticos recientes en el Error Log.</li>' END, '
                    ', CASE WHEN @PLE < 300 THEN CONCAT('<li style="color: #dc3545; font-weight: bold;">PLE bajo (', CAST(@PLE AS VARCHAR(10)), ' segundos).</li>') ELSE CONCAT('<li>PLE en niveles normales (', CAST(@PLE AS VARCHAR(10)), ' seg).</li>') END, '
                    <li>Transacciones abiertas activas: <b>', CAST(@ActiveTransCount AS VARCHAR(10)), '</b> | Memoria SO Usada: <b>', CAST(@OSMemPct AS VARCHAR(3)), '%</b> | Memoria SQL Asignada: <b>', CAST(@SQLMemGB AS VARCHAR(10)), ' GB</b>.</li>
                  </ul>
                </td>
              </tr>
            </table>
            <p style="margin: 10px 0 0 0; font-size: 9px; color: #6c757d; text-align: center;">Reporte automático generado por Instancia SQL Server - ', @ServerName, '</p>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>');

-- Envío por correo usando Database Mail (Descomenta cuando configures tu perfil)
/*
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'TuPerfilDeCorreo',
    @recipients = 'dba_team@tuempresa.com',
    @subject = @ServerName + ' - Monitor Operativo SQL Server',
    @body = @Html,
    @body_format = 'HTML';
*/

-- Si deseas probar el HTML directamente en una pestaña de resultados:
SELECT @Html AS ReporteHTML;
