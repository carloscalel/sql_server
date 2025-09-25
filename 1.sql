-- Base de datos
CREATE TABLE #DB_SpaceUsed (
    database_name SYSNAME,
    database_size NVARCHAR(50),
    unallocated_space NVARCHAR(50),
    reserved NVARCHAR(50),
    data NVARCHAR(50),
    index_size NVARCHAR(50),
    unused NVARCHAR(50)
);

INSERT INTO #DB_SpaceUsed
EXEC sp_spaceused
WITH RESULT SETS (
    (
        database_name SYSNAME,
        database_size NVARCHAR(50),
        unallocated_space NVARCHAR(50),
        reserved NVARCHAR(50),
        data NVARCHAR(50),
        index_size NVARCHAR(50),
        unused NVARCHAR(50)
    )
);

SELECT * FROM #DB_SpaceUsed;