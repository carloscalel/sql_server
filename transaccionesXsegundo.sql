-- Script para monitorear las transacciones por segundo en SQL Server

DECLARE @ts_now BIGINT;
DECLARE @ts_begin BIGINT;
DECLARE @transactions_now BIGINT;
DECLARE @transactions_begin BIGINT;

-- Obtener la marca de tiempo inicial y el contador de transacciones
SELECT @ts_begin = cpu_ticks / (cpu_ticks / ms_ticks),
       @transactions_begin = cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Transactions/sec';

-- Esperar un breve intervalo de tiempo (en milisegundos) para calcular la tasa
WAITFOR DELAY '00:00:05'; -- Puedes ajustar este valor según necesites

-- Obtener la marca de tiempo actual y el contador de transacciones actual
SELECT @ts_now = cpu_ticks / (cpu_ticks / ms_ticks),
       @transactions_now = cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Transactions/sec';

-- Calcular la diferencia en las marcas de tiempo (en segundos)
DECLARE @elapsed_time_seconds DECIMAL(10, 2);
SET @elapsed_time_seconds = CAST((@ts_now - @ts_begin) AS DECIMAL(20, 2)) / CAST((cpu_ticks / ms_ticks) AS DECIMAL(20, 2));

-- Calcular la diferencia en el número de transacciones
DECLARE @transaction_difference INT;
SET @transaction_difference = @transactions_now - @transactions_begin;

-- Calcular las transacciones por segundo
DECLARE @transactions_per_second DECIMAL(10, 2);
IF @elapsed_time_seconds > 0
    SET @transactions_per_second = CAST(@transaction_difference AS DECIMAL(10, 2)) / @elapsed_time_seconds;
ELSE
    SET @transactions_per_second = 0;

-- Mostrar el resultado
SELECT
    GETDATE() AS CollectionTime,
    @transactions_per_second AS TransactionsPerSecond;
