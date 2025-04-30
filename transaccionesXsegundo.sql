-- Script para medir transacciones por segundo en SQL Server
-- Muestra el total de transacciones y las diferencia para calcular TPS

-- Paso 1: Obtener contador inicial
SELECT 
    instance_name,
    cntr_value AS [Transactions],
    CURRENT_TIMESTAMP AS [StartTime]
INTO #TransStart
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Transactions/sec'
AND instance_name = '_Total'

-- Esperar un intervalo (ej. 5 segundos)
WAITFOR DELAY '00:00:05'

-- Paso 2: Obtener contador final
SELECT 
    instance_name,
    cntr_value AS [Transactions],
    CURRENT_TIMESTAMP AS [EndTime]
INTO #TransEnd
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Transactions/sec'
AND instance_name = '_Total'

-- Paso 3: Calcular TPS en el intervalo
SELECT 
    E.instance_name,
    (E.Transactions - S.Transactions) / 
    DATEDIFF(SECOND, S.StartTime, E.EndTime) AS [TPS]
FROM #TransStart S
JOIN #TransEnd E ON S.instance_name = E.instance_name

-- Limpiar tablas temporales
DROP TABLE #TransStart
DROP TABLE #TransEnd