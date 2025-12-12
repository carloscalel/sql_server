DECLARE 
    @TableName SYSNAME = 'dbo.TuTabla',
    @KeyColumns NVARCHAR(MAX) = 'Col1,Col2';   -- columnas del índice

DECLARE @ObjectID INT = OBJECT_ID(@TableName);

-- tamaño total de filas
DECLARE @RowCount BIGINT;
SELECT @RowCount = SUM(row_count)
FROM sys.dm_db_partition_stats
WHERE object_id = @ObjectID
  AND index_id IN (0,1); -- heap o clustered

-- tamaño total de columnas clave (bytes)
DECLARE @KeySizeBytes INT;

SELECT @KeySizeBytes = SUM(
        CASE 
            WHEN t.name IN ('varchar','nvarchar','varbinary')
                THEN CASE c.max_length WHEN -1 THEN 100 ELSE c.max_length END
            ELSE c.max_length
        END
    )
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = @ObjectID
  AND c.name IN (
        SELECT LTRIM(RTRIM(value))
        FROM STRING_SPLIT(@KeyColumns, ',')
    );

-- estimación final
SELECT 
    @RowCount AS TotalRows,
    @KeySizeBytes AS KeyBytesPerRow,
    (@RowCount * @KeySizeBytes * 1.2) / 1024 / 1024 AS EstimatedIndexSizeMB;