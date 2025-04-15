-- Script para verificar el espacio utilizado por los archivos tempdb en SQL Server

-- Paso 1: Verificar el tamaño actual y el espacio libre de los archivos de datos de tempdb
SELECT
    name AS FileName,
    size * 8.0 / 1024 AS FileSizeMB,
    FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS SpaceUsedMB,
    size * 8.0 / 1024 - FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS FreeSpaceMB
FROM sys.database_files
WHERE database_id = DB_ID('tempdb')
AND type_desc = 'ROWS';

GO

-- Paso 2: Verificar el tamaño actual y el espacio libre de los archivos de log de tempdb
SELECT
    name AS FileName,
    size * 8.0 / 1024 AS FileSizeMB,
    FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS SpaceUsedMB,
    size * 8.0 / 1024 - FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS FreeSpaceMB
FROM sys.database_files
WHERE database_id = DB_ID('tempdb')
AND type_desc = 'LOG';

GO

-- Paso 3: (Opcional) Verificar el espacio utilizado por las tablas internas de tempdb
-- Esto puede dar una idea de qué objetos están consumiendo más espacio.
SELECT
    SUM(internal_table_reserved_page_count) * 8.0 / 1024 AS InternalTablesReservedMB,
    SUM(user_table_reserved_page_count) * 8.0 / 1024 AS UserTablesReservedMB,
    SUM(version_store_reserved_page_count) * 8.0 / 1024 AS VersionStoreReservedMB,
    SUM(sort_pages_reserved) * 8.0 / 1024 AS SortPagesReservedMB,
    SUM(lob_reserved_page_count) * 8.0 / 1024 AS LOBReservedMB
FROM sys.dm_db_file_space_usage;

GO

-- Paso 4: (Opcional) Verificar el espacio utilizado por las sesiones individuales en tempdb
-- Requiere permisos VIEW SERVER STATE.
SELECT
    s.session_id,
    login_name,
    program_name,
    SUM(tsu.user_objects_alloc_page_count) * 8.0 / 1024 AS UserObjectsAllocatedMB,
    SUM(tsu.user_objects_dealloc_page_count) * 8.0 / 1024 AS UserObjectsDeallocatedMB,
    SUM(tsu.internal_objects_alloc_page_count) * 8.0 / 1024 AS InternalObjectsAllocatedMB,
    SUM(tsu.internal_objects_dealloc_page_count) * 8.0 / 1024 AS InternalObjectsDeallocatedMB
FROM sys.dm_db_task_space_usage AS tsu
INNER JOIN sys.dm_exec_sessions AS s
ON tsu.session_id = s.session_id
GROUP BY s.session_id, login_name, program_name
ORDER BY SUM(tsu.user_objects_alloc_page_count) DESC;

GO
