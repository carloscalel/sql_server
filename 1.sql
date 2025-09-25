-- Tamaño total de la BD y espacio no asignado
SELECT 
    DB_NAME() AS database_name,
    CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(10,2)) AS database_size_MB,
    CAST(SUM(size) * 8.0 / 1024 
        - CAST(SUM(FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(10,2)) AS DECIMAL(10,2)) AS unallocated_space_MB
FROM sys.database_files;

-- Detalle del espacio usado en la BD
SELECT 
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10,2)) AS reserved_MB,
    CAST(SUM(a.used_pages) * 8.0 / 1024 AS DECIMAL(10,2)) AS data_MB,
    CAST((SUM(a.used_pages) - SUM(a.data_pages)) * 8.0 / 1024 AS DECIMAL(10,2)) AS index_size_MB,
    CAST((SUM(a.total_pages) - SUM(a.used_pages)) * 8.0 / 1024 AS DECIMAL(10,2)) AS unused_MB
FROM sys.allocation_units a
JOIN sys.partitions p 
    ON a.container_id = p.hobt_id;