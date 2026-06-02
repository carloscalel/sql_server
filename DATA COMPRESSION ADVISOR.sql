 
/* ============================================================
  SQL SERVER DATA COMPRESSION ADVISOR (V2 - CORREGIDO)
  Compatible con SQL Server 2016 en adelante

  Objetivo:
  - Analizar tablas >= @MinTableSizeGB
  - Incluir HEAPs, clustered indexes y nonclustered indexes
  - Estimar ROW y PAGE
  - Recomendar ROW / PAGE / NO_APLICAR
  - Generar script de aplicación (ejecución MANUAL)

  Modo seguro:
  - Solo análisis y generación de scripts
  - NO ejecuta cambios automáticamente
  ============================================================ */

SET NOCOUNT ON;

/* ============================================================
  1. PARÁMETROS PRINCIPALES
  ============================================================ */
DECLARE 
   @MinTableSizeGB DECIMAL(18,2) = 20.00,  -- Solo tablas >= 20 GB
   @TopN INT = NULL,                       -- NULL = todas arriba de 20 GB.
   @AnalyzeOnlyUncompressed BIT = 1,       -- 1 = solo objetos sin compresión. 0 = analiza también ROW/PAGE existentes

   @MinSavingPct DECIMAL(10,2) = 10.00,    -- Ahorro mínimo para recomendar
   @PageExtraPct DECIMAL(10,2) = 5.00,     -- PAGE debe superar ROW por estos puntos para preferir PAGE
   @HighWriteRatio DECIMAL(10,2) = 0.40,   -- Si escrituras > 40%, se penaliza PAGE

   @PreferOnline BIT = 1,                  -- 1 = intentar generar ONLINE = ON
   @ForceOnlineEvenIfUndetected BIT = 0,   -- 1 = fuerza ONLINE aunque la edición no sea detectada como compatible
   @UseLowPriorityWait BIT = 1,            -- Usa WAIT_AT_LOW_PRIORITY cuando ONLINE = ON
   @LowPriorityMaxDurationMinutes INT = 5, -- Tiempo máximo esperando bloqueo en baja prioridad
   @AbortAfterWait NVARCHAR(10) = N'SELF', -- NONE | SELF | BLOCKERS. Recomendado: SELF
   @MaxDOP INT = 2,                        -- NULL = no especificar MAXDOP
   @IncludeStatsUpdate BIT = 1,            -- Incluir UPDATE STATISTICS después del rebuild
   @GenerateSeparateScripts BIT = 0,       -- 1 = script por objeto, 0 = script único

   @LockTimeoutSeconds INT = 30;           -- Evita esperas largas en análisis

/* ============================================================
  2. VALIDACIONES BÁSICAS
  ============================================================ */
IF NOT (IS_MEMBER('db_owner') = 1 OR HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'ALTER') = 1)
BEGIN
   PRINT 'ADVERTENCIA: Se requieren permisos ALTER en la base de datos para aplicar compresión.';
   PRINT 'Los scripts generados podrían no ejecutarse correctamente.' + CHAR(13) + CHAR(10);
END;

IF @AbortAfterWait NOT IN (N'NONE', N'SELF', N'BLOCKERS')
BEGIN
   SET @AbortAfterWait = N'SELF';
   PRINT 'NOTA: @AbortAfterWait inválido, se estableció a SELF';
END;

IF @LowPriorityMaxDurationMinutes IS NULL OR @LowPriorityMaxDurationMinutes < 0
BEGIN
   SET @LowPriorityMaxDurationMinutes = 5;
   PRINT 'NOTA: @LowPriorityMaxDurationMinutes inválido, se estableció a 5';
END;

IF @LockTimeoutSeconds IS NOT NULL AND @LockTimeoutSeconds > 0
BEGIN
   DECLARE @LockTimeoutMS INT = @LockTimeoutSeconds * 1000;
   SET LOCK_TIMEOUT @LockTimeoutMS;
   PRINT 'NOTA: Lock timeout establecido a ' + CAST(@LockTimeoutSeconds AS VARCHAR) + ' segundos' + CHAR(13) + CHAR(10);
END;

/* ============================================================
  3. DETECCIÓN BÁSICA DE EDICIÓN PARA ONLINE
  ============================================================ */
DECLARE 
   @Edition NVARCHAR(200) = CONVERT(NVARCHAR(200), SERVERPROPERTY('Edition')),
   @ProductVersion NVARCHAR(100) = CONVERT(NVARCHAR(100), SERVERPROPERTY('ProductVersion')),
   @EngineEdition INT = CONVERT(INT, SERVERPROPERTY('EngineEdition')),
   @OnlineSupportedLikely BIT = 0,
   @UseOnline BIT = 0,
   @OnlineOption NVARCHAR(500),
   @MaxDopOption NVARCHAR(100),
   @OnlineNote NVARCHAR(500);

IF (
   @Edition LIKE N'%Enterprise%' OR
   @Edition LIKE N'%Developer%' OR
   @Edition LIKE N'%Evaluation%' OR
   @EngineEdition IN (5, 8) -- Azure SQL Database / Managed Instance
)
BEGIN
   SET @OnlineSupportedLikely = 1;
END;

SET @UseOnline = CASE WHEN @PreferOnline = 1 AND (@OnlineSupportedLikely = 1 OR @ForceOnlineEvenIfUndetected = 1) THEN 1 ELSE 0 END;

SET @OnlineOption =
   CASE 
       WHEN @UseOnline = 1 AND @UseLowPriorityWait = 1 THEN
           N', ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = ' + CONVERT(NVARCHAR(20), @LowPriorityMaxDurationMinutes) + N' MINUTES, ABORT_AFTER_WAIT = ' + @AbortAfterWait + N'))'
       WHEN @UseOnline = 1 AND @UseLowPriorityWait = 0 THEN N', ONLINE = ON'
       ELSE N', ONLINE = OFF'
   END;

SET @MaxDopOption = CASE WHEN @MaxDOP IS NOT NULL AND @MaxDOP > 0 THEN N', MAXDOP = ' + CONVERT(NVARCHAR(20), @MaxDOP) ELSE N'' END;

SET @OnlineNote =
   CASE 
       WHEN @PreferOnline = 1 AND @UseOnline = 1 THEN N'✓ Se generará ONLINE = ON (compatible con la edición detectada)'
       WHEN @PreferOnline = 1 AND @UseOnline = 0 THEN N'⚠ ONLINE fue solicitado, pero la edición NO es compatible. Se generará ONLINE = OFF.'
       ELSE N'✗ Se generará ONLINE = OFF'
   END;

PRINT '╔════════════════════════════════════════════════════════════════╗';
PRINT '║        DATA COMPRESSION ADVISOR - CONFIGURACIÓN INICIAL        ║';
PRINT '╚════════════════════════════════════════════════════════════════╝';
PRINT 'Configuración:';
PRINT '  - Tamaño mínimo: ' + CAST(@MinTableSizeGB AS VARCHAR) + ' GB';
PRINT '  - Ahorro mínimo requerido: ' + CAST(@MinSavingPct AS VARCHAR) + '%';
PRINT '  - Preferir ONLINE: ' + CASE WHEN @PreferOnline = 1 THEN 'SÍ' ELSE 'NO' END;
PRINT '  - ' + @OnlineNote;
PRINT '  - Edición detectada: ' + @Edition;
PRINT '  - Versión: ' + @ProductVersion;
PRINT '  - Modo: SOLO ANÁLISIS Y GENERACIÓN DE SCRIPTS (NO ejecución automática)';
PRINT '════════════════════════════════════════════════════════════════' + CHAR(13) + CHAR(10);

/* ============================================================
  4. TABLAS TEMPORALES
  ============================================================ */
DROP TABLE IF EXISTS #Candidates;
DROP TABLE IF EXISTS #RawEstimate;
DROP TABLE IF EXISTS #Estimates;
DROP TABLE IF EXISTS #Errors;
DROP TABLE IF EXISTS #Results;

CREATE TABLE #Candidates (
   object_id INT NOT NULL, schema_name SYSNAME NOT NULL, object_name SYSNAME NOT NULL, table_reserved_gb DECIMAL(18,2) NOT NULL,
   index_id INT NOT NULL, index_name SYSNAME NULL, index_type_desc NVARCHAR(60) NOT NULL, partition_number INT NOT NULL, partition_count INT NOT NULL,
   rows_count BIGINT NOT NULL, reserved_mb DECIMAL(18,2) NOT NULL, current_compression NVARCHAR(60) NOT NULL,
   user_seeks BIGINT NOT NULL, user_scans BIGINT NOT NULL, user_lookups BIGINT NOT NULL, user_updates BIGINT NOT NULL
);

CREATE TABLE #RawEstimate (
   object_name SYSNAME, schema_name SYSNAME, index_id INT, partition_number INT,
   size_with_current_compression_setting BIGINT, size_with_requested_compression_setting BIGINT,
   sample_size_with_current_compression_setting BIGINT, sample_size_with_requested_compression_setting BIGINT
);

CREATE TABLE #Estimates (
   schema_name SYSNAME, object_name SYSNAME, index_id INT, partition_number INT, compression_type NVARCHAR(10),
   current_size_kb BIGINT, estimated_size_kb BIGINT, sample_current_size_kb BIGINT, sample_estimated_size_kb BIGINT
);

CREATE TABLE #Errors (
   error_id INT IDENTITY(1,1) PRIMARY KEY, schema_name SYSNAME, object_name SYSNAME, index_id INT,
   partition_number INT, compression_type NVARCHAR(10), error_message NVARCHAR(4000), error_date DATETIME2(0) DEFAULT SYSDATETIME()
);

CREATE TABLE #Results (
   result_id INT IDENTITY(1,1) PRIMARY KEY, schema_name SYSNAME, object_name SYSNAME, object_type NVARCHAR(80),
   index_id INT, index_name SYSNAME NULL, index_type_desc NVARCHAR(60), partition_number INT, partition_count INT,
   table_reserved_gb DECIMAL(18,2), object_reserved_mb DECIMAL(18,2), rows_count BIGINT, current_compression NVARCHAR(60),
   current_size_mb DECIMAL(18,2), estimated_row_size_mb DECIMAL(18,2), estimated_page_size_mb DECIMAL(18,2),
   row_saving_pct DECIMAL(10,2), page_saving_pct DECIMAL(10,2),
   user_seeks BIGINT, user_scans BIGINT, user_lookups BIGINT, user_updates BIGINT, write_ratio DECIMAL(10,2),
   recommendation NVARCHAR(30), reason NVARCHAR(500), suggested_sql NVARCHAR(MAX), estimated_time_minutes INT NULL
);

/* ============================================================
  5. IDENTIFICAR CANDIDATOS
  ============================================================ */
PRINT 'Paso 1: Identificando tablas candidatas...';

;WITH IndexSizeInfoRaw AS (
   SELECT t.object_id, s.name AS schema_name, t.name AS object_name, i.index_id, i.name AS index_name, i.type_desc AS index_type_desc,
          ps.partition_number, ps.row_count AS rows_count, p.data_compression_desc AS current_compression,
          CONVERT(DECIMAL(18,2), ps.reserved_page_count * 8.0 / 1024.0) AS reserved_mb
   FROM sys.tables t
   INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
   INNER JOIN sys.indexes i ON t.object_id = i.object_id
   INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
   INNER JOIN sys.partitions p ON ps.object_id = p.object_id AND i.index_id = p.index_id AND ps.partition_number = p.partition_number
   WHERE t.is_ms_shipped = 0 AND t.is_memory_optimized = 0 AND i.type IN (0, 1, 2) AND i.is_disabled = 0 AND i.is_hypothetical = 0 AND ps.row_count > 0
),
IndexSizeInfo AS (
   SELECT *, COUNT(*) OVER (PARTITION BY object_id, index_id) AS partition_count FROM IndexSizeInfoRaw
),
TableTotals AS (
   SELECT object_id, schema_name, object_name, CONVERT(DECIMAL(18,2), SUM(reserved_mb) / 1024.0) AS table_reserved_gb
   FROM IndexSizeInfo GROUP BY object_id, schema_name, object_name
),
FilteredTables AS (
   SELECT *, ROW_NUMBER() OVER (ORDER BY table_reserved_gb DESC) AS rn FROM TableTotals WHERE table_reserved_gb >= @MinTableSizeGB
)
INSERT INTO #Candidates
SELECT isi.object_id, isi.schema_name, isi.object_name, ft.table_reserved_gb, isi.index_id, isi.index_name, isi.index_type_desc,
      isi.partition_number, isi.partition_count, isi.rows_count, isi.reserved_mb, isi.current_compression,
      ISNULL(us.user_seeks, 0), ISNULL(us.user_scans, 0), ISNULL(us.user_lookups, 0), ISNULL(us.user_updates, 0)
FROM IndexSizeInfo isi
INNER JOIN FilteredTables ft ON isi.object_id = ft.object_id
LEFT JOIN sys.dm_db_index_usage_stats us ON us.database_id = DB_ID() AND us.object_id = isi.object_id AND us.index_id = isi.index_id
WHERE (@TopN IS NULL OR ft.rn <= @TopN) AND (@AnalyzeOnlyUncompressed = 0 OR isi.current_compression = N'NONE');

DECLARE @CandidateCount INT = (SELECT COUNT(*) FROM #Candidates);
PRINT '  ✓ Candidatos encontrados: ' + CAST(@CandidateCount AS VARCHAR) + ' objetos (particiones)' + CHAR(13) + CHAR(10);

/* ============================================================
  6. ESTIMAR ROW Y PAGE
  ============================================================ */
PRINT 'Paso 2: Estimando ahorro de compresión...';
DECLARE @SchemaName SYSNAME, @ObjectName SYSNAME, @IndexId INT, @PartitionNumber INT, @Compression NVARCHAR(10), @Progress INT = 0, @TotalEstimate INT;
SELECT @TotalEstimate = COUNT(*) * 2 FROM #Candidates;

DECLARE candidate_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT schema_name, object_name, index_id, partition_number FROM #Candidates ORDER BY table_reserved_gb DESC, reserved_mb DESC;

OPEN candidate_cursor;
FETCH NEXT FROM candidate_cursor INTO @SchemaName, @ObjectName, @IndexId, @PartitionNumber;

WHILE @@FETCH_STATUS = 0
BEGIN
   -- ROW
   SET @Compression = N'ROW'; SET @Progress = @Progress + 1;
   IF @Progress % 10 = 0 OR @Progress = 1 PRINT '    Progreso: ' + CAST(@Progress AS VARCHAR) + '/' + CAST(@TotalEstimate AS VARCHAR);
   BEGIN TRY
       TRUNCATE TABLE #RawEstimate;
       INSERT INTO #RawEstimate EXEC sys.sp_estimate_data_compression_savings @SchemaName, @ObjectName, @IndexId, @PartitionNumber, @Compression;
       INSERT INTO #Estimates SELECT schema_name, object_name, index_id, partition_number, @Compression, size_with_current_compression_setting, size_with_requested_compression_setting, sample_size_with_current_compression_setting, sample_size_with_requested_compression_setting FROM #RawEstimate;
   END TRY
   BEGIN CATCH
       INSERT INTO #Errors (schema_name, object_name, index_id, partition_number, compression_type, error_message) VALUES (@SchemaName, @ObjectName, @IndexId, @PartitionNumber, @Compression, ERROR_MESSAGE());
   END CATCH;

   -- PAGE
   SET @Compression = N'PAGE'; SET @Progress = @Progress + 1;
   BEGIN TRY
       TRUNCATE TABLE #RawEstimate;
       INSERT INTO #RawEstimate EXEC sys.sp_estimate_data_compression_savings @SchemaName, @ObjectName, @IndexId, @PartitionNumber, @Compression;
       INSERT INTO #Estimates SELECT schema_name, object_name, index_id, partition_number, @Compression, size_with_current_compression_setting, size_with_requested_compression_setting, sample_size_with_current_compression_setting, sample_size_with_requested_compression_setting FROM #RawEstimate;
   END TRY
   BEGIN CATCH
       INSERT INTO #Errors (schema_name, object_name, index_id, partition_number, compression_type, error_message) VALUES (@SchemaName, @ObjectName, @IndexId, @PartitionNumber, @Compression, ERROR_MESSAGE());
   END CATCH;

   FETCH NEXT FROM candidate_cursor INTO @SchemaName, @ObjectName, @IndexId, @PartitionNumber;
END;
CLOSE candidate_cursor; DEALLOCATE candidate_cursor;
PRINT '  ✓ Estimaciones completadas' + CHAR(13) + CHAR(10);

/* ============================================================
  7. GENERAR RECOMENDACIONES Y SCRIPTS (CORREGIDO)
  ============================================================ */
PRINT 'Paso 3: Generando recomendaciones y scripts...';

;WITH Pivoted AS (
   SELECT c.schema_name, c.object_name, c.table_reserved_gb, c.index_id, c.index_name, c.index_type_desc, c.partition_number, c.partition_count, c.rows_count, c.reserved_mb, c.current_compression, c.user_seeks, c.user_scans, c.user_lookups, c.user_updates,
          er.current_size_kb AS row_current_size_kb, er.estimated_size_kb AS row_estimated_size_kb, ep.current_size_kb AS page_current_size_kb, ep.estimated_size_kb AS page_estimated_size_kb
   FROM #Candidates c
   LEFT JOIN #Estimates er ON er.schema_name = c.schema_name AND er.object_name = c.object_name AND er.index_id = c.index_id AND er.partition_number = c.partition_number AND er.compression_type = N'ROW'
   LEFT JOIN #Estimates ep ON ep.schema_name = c.schema_name AND ep.object_name = c.object_name AND ep.index_id = c.index_id AND ep.partition_number = c.partition_number AND ep.compression_type = N'PAGE'
),
Calc AS (
   SELECT *, COALESCE(row_current_size_kb, page_current_size_kb) AS current_size_kb,
          -- CORREGIDO: Se cambiaron las referencias erróneas de _mb a _kb para que coincidan con las columnas del paso anterior
          CONVERT(DECIMAL(10,2), (COALESCE(row_current_size_kb, page_current_size_kb) - row_estimated_size_kb) * 100.0 / NULLIF(COALESCE(row_current_size_kb, page_current_size_kb), 0)) AS row_saving_pct,
          CONVERT(DECIMAL(10,2), (COALESCE(row_current_size_kb, page_current_size_kb) - page_estimated_size_kb) * 100.0 / NULLIF(COALESCE(row_current_size_kb, page_current_size_kb), 0)) AS page_saving_pct,
          CONVERT(DECIMAL(10,2), user_updates * 1.0 / NULLIF(user_seeks + user_scans + user_lookups + user_updates, 0)) AS write_ratio,
          CONVERT(INT, reserved_mb / 1024.0 / 10.0 * 60) AS estimated_minutes
   FROM Pivoted
),
Recommended AS (
   SELECT *,
          CASE 
              WHEN current_size_kb IS NULL THEN N'SIN_ESTIMACION'
              WHEN ISNULL(row_saving_pct, 0) < @MinSavingPct AND ISNULL(page_saving_pct, 0) < @MinSavingPct THEN N'NO_APLICAR'
              WHEN ISNULL(page_saving_pct, 0) >= @MinSavingPct AND ISNULL(page_saving_pct, 0) - ISNULL(row_saving_pct, 0) >= @PageExtraPct AND ISNULL(write_ratio, 0) < @HighWriteRatio THEN N'PAGE'
              WHEN ISNULL(row_saving_pct, 0) >= @MinSavingPct THEN N'ROW'
              WHEN ISNULL(page_saving_pct, 0) >= @MinSavingPct AND ISNULL(write_ratio, 0) < @HighWriteRatio THEN N'PAGE'
              ELSE N'NO_APLICAR'
          END AS recommendation,
          CASE 
              WHEN current_size_kb IS NULL THEN N'No se pudo obtener estimación.'
              WHEN ISNULL(row_saving_pct, 0) < @MinSavingPct AND ISNULL(page_saving_pct, 0) < @MinSavingPct THEN N'Ahorro estimado bajo.'
              WHEN ISNULL(page_saving_pct, 0) >= @MinSavingPct AND ISNULL(page_saving_pct, 0) - ISNULL(row_saving_pct, 0) >= @PageExtraPct AND ISNULL(write_ratio, 0) < @HighWriteRatio THEN N'PAGE ofrece mayor ahorro y bajas escrituras.'
              WHEN ISNULL(row_saving_pct, 0) >= @MinSavingPct THEN N'ROW ofrece ahorro aceptable con menor costo de CPU.'
              ELSE N'Revisar manualmente.'
          END AS reason
   FROM Calc
)
INSERT INTO #Results
SELECT schema_name, object_name, CASE WHEN index_id = 0 THEN 'HEAP' WHEN index_id = 1 THEN 'CLUSTERED INDEX' ELSE 'NONCLUSTERED INDEX' END,
      index_id, index_name, index_type_desc, partition_number, partition_count, table_reserved_gb, reserved_mb, rows_count, current_compression,
      CONVERT(DECIMAL(18,2), current_size_kb / 1024.0), 
      CONVERT(DECIMAL(18,2), row_estimated_size_kb / 1024.0), -- Aquí se asigna correctamente usando _kb
      CONVERT(DECIMAL(18,2), page_estimated_size_kb / 1024.0), -- Aquí se asigna correctamente usando _kb
      row_saving_pct, page_saving_pct, user_seeks, user_scans, user_lookups, user_updates, write_ratio, recommendation, reason,
      CASE 
          WHEN recommendation IN ('ROW', 'PAGE') THEN
              N'-- ' + CASE WHEN index_id = 0 THEN 'HEAP' ELSE 'INDEX [' + ISNULL(index_name, '') + N']' END + N' en [' + schema_name + N'].[' + object_name + N']' + CHAR(13) +
              N'ALTER ' + CASE WHEN index_id = 0 THEN N'TABLE [' + schema_name + N'].[' + object_name + N']' ELSE N'INDEX [' + ISNULL(index_name, N'') + N'] ON [' + schema_name + N'].[' + object_name + N']' END + 
              N' REBUILD ' + CASE WHEN partition_count > 1 THEN N'PARTITION = ' + CAST(partition_number AS VARCHAR) + N' ' ELSE N'' END +
              N'WITH (DATA_COMPRESSION = ' + recommendation + @OnlineOption + @MaxDopOption + N');' +
              CASE WHEN @IncludeStatsUpdate = 1 AND index_id IN (0, 1) THEN CHAR(13) + N'UPDATE STATISTICS [' + schema_name + N'].[' + object_name + N'] WITH FULLSCAN;' + CHAR(13) ELSE CHAR(13) END
          ELSE NULL
      END, estimated_minutes
FROM Recommended WHERE recommendation IN ('ROW', 'PAGE', 'NO_APLICAR');

PRINT '  ✓ Recomendaciones generadas' + CHAR(13) + CHAR(10);

/* ============================================================
  8. REPORTE DE ERRORES / 9. MOSTRAR RESULTADOS
  ============================================================ */
IF EXISTS (SELECT 1 FROM #Errors)
BEGIN
   SELECT '⚠ ERROR EN ANÁLISIS' AS [Status], schema_name, object_name, compression_type, error_message FROM #Errors;
END;

SELECT recommendation, COUNT(*) AS ObjectCount, CAST(SUM(current_size_mb) / 1024.0 AS DECIMAL(18,2)) AS TotalCurrentGB,
      CAST(SUM(CASE WHEN recommendation = 'ROW' THEN current_size_mb * (1 - row_saving_pct/100) WHEN recommendation = 'PAGE' THEN current_size_mb * (1 - page_saving_pct/100) ELSE current_size_mb END) / 1024.0 AS DECIMAL(18,2)) AS TotalEstimatedGB
FROM #Results GROUP BY recommendation;

SELECT schema_name + '.' + object_name AS Objeto, object_type AS Tipo, ISNULL(index_name, 'HEAP') AS IndexName, partition_number AS Part, CAST(current_size_mb / 1024.0 AS DECIMAL(18,2)) AS SizeGB, recommendation AS Rec, write_ratio AS Writes, estimated_time_minutes AS EstMin
FROM #Results WHERE recommendation IN ('ROW', 'PAGE') ORDER BY table_reserved_gb DESC;

/* ============================================================
  10. GENERAR SCRIPT COMPLETO PARA EJECUCIÓN MANUAL
  ============================================================ */
PRINT '╔════════════════════════════════════════════════════════════════╗';
PRINT '║                   SCRIPT PARA EJECUCIÓN MANUAL                 ║';
PRINT '╚════════════════════════════════════════════════════════════════╝';

IF @GenerateSeparateScripts = 0
BEGIN
   PRINT 'USE [' + DB_NAME() + '];'; PRINT 'GO'; PRINT '';
   DECLARE @FullScript NVARCHAR(MAX) = '';
   SELECT @FullScript = @FullScript + suggested_sql + CHAR(13) + CHAR(10) + 'GO' + CHAR(13) + CHAR(10) FROM #Results WHERE suggested_sql IS NOT NULL ORDER BY CASE WHEN index_id IN (0, 1) THEN 1 ELSE 2 END, object_reserved_mb DESC;
   PRINT @FullScript;
END
ELSE
BEGIN
   DECLARE @SqlToPrint NVARCHAR(MAX);
   DECLARE @RecType NVARCHAR(30);
   DECLARE @Counter INT = 1;
   DECLARE @TotalScripts INT = (SELECT COUNT(*) FROM #Results WHERE suggested_sql IS NOT NULL);
   
   DECLARE script_cursor CURSOR FOR
   SELECT suggested_sql, schema_name, object_name, index_id, recommendation FROM #Results WHERE suggested_sql IS NOT NULL ORDER BY CASE WHEN index_id IN (0, 1) THEN 1 ELSE 2 END, object_reserved_mb DESC;
   
   OPEN script_cursor;
   FETCH NEXT FROM script_cursor INTO @SqlToPrint, @SchemaName, @ObjectName, @IndexId, @RecType;
   
   WHILE @@FETCH_STATUS = 0
   BEGIN
       PRINT '-- ============================================================';
       PRINT '-- SCRIPT ' + CAST(@Counter AS VARCHAR) + ' DE ' + CAST(@TotalScripts AS VARCHAR);
       PRINT '-- OBJETO: [' + @SchemaName + '].[' + @ObjectName + ']';
       PRINT '-- COMPRESIÓN RECOMENDADA: ' + @RecType;
       PRINT '-- ============================================================';
       PRINT @SqlToPrint; 
       PRINT 'GO'; PRINT '';
       
       SET @Counter = @Counter + 1;
       FETCH NEXT FROM script_cursor INTO @SqlToPrint, @SchemaName, @ObjectName, @IndexId, @RecType;
   END;
   CLOSE script_cursor; DEALLOCATE script_cursor;
END;

/* ============================================================
  LIMPIEZA FINAL
  ============================================================ */
DROP TABLE IF EXISTS #Candidates; DROP TABLE IF EXISTS #RawEstimate; DROP TABLE IF EXISTS #Estimates; DROP TABLE IF EXISTS #Errors; DROP TABLE IF EXISTS #Results;
