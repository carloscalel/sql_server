INSERT INTO ##TableSpaceAllDB
SELECT
    DB_NAME() AS DatabaseName,
    s.name AS SchemaName,
    t.name AS TableName,

    -- ROWS correctos
    SUM(CASE WHEN i.index_id IN (0,1) THEN p.rows ELSE 0 END) AS NumRows,

    -- RESERVED
    SUM(a.total_pages) * 8 AS ReservedKB,

    -- DATA (heap o clustered)
    SUM(
        CASE 
            WHEN i.index_id IN (0,1) THEN a.used_pages
            ELSE 0
        END
    ) * 8 AS DataKB,

    -- INDEX (nonclustered)
    SUM(
        CASE 
            WHEN i.index_id > 1 THEN a.used_pages
            ELSE 0
        END
    ) * 8 AS IndexKB,

    -- UNUSED
    SUM(a.total_pages - a.used_pages) * 8 AS UnusedKB

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