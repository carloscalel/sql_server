CREATE TABLE #DB_SpaceUsed (
    database_name SYSNAME,
    database_size NVARCHAR(50),
    unallocated_space NVARCHAR(50)
);

CREATE TABLE #DB_SpaceUsedDetail (
    reserved NVARCHAR(50),
    data NVARCHAR(50),
    index_size NVARCHAR(50),
    unused NVARCHAR(50)
);

-- Primer resultset
INSERT INTO #DB_SpaceUsed (database_name, database_size, unallocated_space)
EXEC sp_spaceused;

-- Segundo resultset
INSERT INTO #DB_SpaceUsedDetail (reserved, data, index_size, unused)
EXEC sp_spaceused;

SELECT * FROM #DB_SpaceUsed;
SELECT * FROM #DB_SpaceUsedDetail;