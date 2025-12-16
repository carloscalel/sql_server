IF OBJECT_ID('tempdb..##TableSpaceAllDB') IS NOT NULL
    DROP TABLE ##TableSpaceAllDB;

CREATE TABLE ##TableSpaceAllDB (
    DatabaseName SYSNAME,
    SchemaName SYSNAME,
    TableName SYSNAME,
    NumRows BIGINT,
    ReservedKB BIGINT,
    DataKB BIGINT,
    IndexKB BIGINT,
    UnusedKB BIGINT
);

DECLARE 
    @DBName SYSNAME,
    @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state_desc = 'ONLINE';

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'
    USE [' + QUOTENAME(@DBName) + N'];

    INSERT INTO ##TableSpaceAllDB
    SELECT
        DB_NAME() AS DatabaseName,
        s.name AS SchemaName,
        t.name AS TableName,
        SUM(p.rows) AS NumRows,
        SUM(a.total_pages) * 8 AS ReservedKB,
        SUM(a.data_pages) * 8 AS DataKB,
        (SUM(a.used_pages) - SUM(a.data_pages)) * 8 AS IndexKB,
        (SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS UnusedKB
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    JOIN sys.indexes i ON t.object_id = i.object_id
    JOIN sys.partitions p 
        ON i.object_id = p.object_id 
       AND i.index_id = p.index_id
    JOIN sys.allocation_units a 
        ON p.partition_id = a.container_id
    WHERE t.is_ms_shipped = 0
    GROUP BY s.name, t.name;
    ';

    EXEC sp_executesql @SQL;

    FETCH NEXT FROM db_cursor INTO @DBName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;