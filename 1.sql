IF OBJECT_ID('tempdb..#Databases') IS NOT NULL
    DROP TABLE #Databases;

CREATE TABLE #Databases (
    RowNum INT IDENTITY(1,1),
    DBName SYSNAME
);

INSERT INTO #Databases (DBName)
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state_desc = 'ONLINE';

DECLARE 
    @i INT = 1,
    @max INT,
    @DBName SYSNAME,
    @SQL NVARCHAR(MAX);

SELECT @max = MAX(RowNum) FROM #Databases;

WHILE @i <= @max
BEGIN
    SELECT @DBName = DBName
    FROM #Databases
    WHERE RowNum = @i;

    SET @SQL = N'
    USE ' + QUOTENAME(@DBName) + N';

    INSERT INTO ##TableSpaceAllDB
    SELECT
        DB_NAME() AS DatabaseName,
        s.name AS SchemaName,
        t.name AS TableName,

        -- ROWS (igual a sp_spaceused)
        SUM(CASE WHEN i.index_id IN (0,1) THEN p.rows ELSE 0 END) AS NumRows,

        -- RESERVED
        SUM(a.total_pages) * 8 AS ReservedKB,

        -- DATA (heap + clustered)
        SUM(
            CASE 
                WHEN i.index_id IN (0,1) 
                THEN a.used_pages 
                ELSE 0 
            END
        ) * 8 AS DataKB,

        -- INDEX (nonclustered)
        SUM(
            CASE 
                WHEN i.index_id > 1 
                THEN a.used_pages 
                ELSE 0 
            END
        ) * 8 AS IndexKB,

        -- UNUSED
        SUM(a.total_pages - a.used_pages) * 8 AS UnusedKB

    FROM sys.tables t
    JOIN sys.schemas s 
        ON t.schema_id = s.schema_id
    JOIN sys.indexes i 
        ON t.object_id = i.object_id
    JOIN sys.partitions p
        ON i.object_id = p.object_id
       AND i.index_id  = p.index_id
    JOIN sys.allocation_units a
        ON p.partition_id = a.container_id
    WHERE t.is_ms_shipped = 0
    GROUP BY s.name, t.name;
    ';

    EXEC sp_executesql @SQL;

    SET @i += 1;
END