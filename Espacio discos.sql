-- Script para ver espacio en disco usado por archivos de SQL Server
-- Sin usar xp_fixeddrives

SELECT 
    vs.volume_mount_point AS [Ruta],
    vs.file_system_type AS [TipoSistema],
    vs.logical_volume_name AS [NombreVolumen],
    CONVERT(DECIMAL(18,2), vs.total_bytes / 1024.0 / 1024 / 1024) AS [Tamaño_GB],
    CONVERT(DECIMAL(18,2), vs.available_bytes / 1024.0 / 1024 / 1024) AS [Libre_GB],
    CONVERT(DECIMAL(18,2), (vs.total_bytes - vs.available_bytes) / 1024.0 / 1024 / 1024) AS [Usado_GB],
    mf.physical_name AS [RutaArchivo],
    DB_NAME(mf.database_id) AS [BaseDeDatos],
    mf.type_desc AS [TipoArchivo],
    CONVERT(DECIMAL(18,2), mf.size * 8.0 / 1024) AS [TamañoArchivo_MB],
    CONVERT(DECIMAL(18,2), CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS INT) * 8.0 / 1024) AS [UsadoEnArchivo_MB],
    CONVERT(DECIMAL(18,2), (mf.size * 8.0 / 1024) - (CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS INT) * 8.0 / 1024)) AS [PorCompactar_MB]
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY vs.volume_mount_point, DB_NAME(mf.database_id)