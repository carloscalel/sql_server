-- Script para ver espacio usado y disponible en discos en SQL Server
-- Incluye: ruta, tipo, tamaño total, libre, usado y espacio por compactar

-- Crear tabla temporal para almacenar información de volúmenes
IF OBJECT_ID('tempdb..#volumes') IS NOT NULL DROP TABLE #volumes

CREATE TABLE #volumes (
    volume_mount_point NVARCHAR(256),
    file_system_type   NVARCHAR(256),
    logical_volume_name NVARCHAR(256),
    total_bytes        BIGINT,
    available_bytes    BIGINT
)

-- Insertar datos desde función extendida
INSERT INTO #volumes
EXEC xp_fixeddrives

-- Alternativa mejorada usando sys.dm_os_volume_stats
SELECT 
    vs.volume_mount_point AS [Ruta],
    vs.file_system_type AS [TipoSistema],
    vs.logical_volume_name AS [NombreVolumen],
    vs.total_bytes / 1024 / 1024 / 1024 AS [Tamaño_GB],
    vs.available_bytes / 1024 / 1024 / 1024 AS [Libre_GB],
    (vs.total_bytes - vs.available_bytes) / 1024 / 1024 / 1024 AS [Usado_GB],
    dbf.filepath,
    dbf.dbname,
    dbf.type_desc AS [TipoArchivo],
    dbf.size_mb,
    dbf.used_space_mb,
    dbf.size_mb - dbf.used_space_mb AS [EspacioPorCompactar_MB]
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
CROSS APPLY (
    SELECT 
        DB_NAME(mf.database_id) AS dbname,
        mf.name AS filelogicalname,
        mf.type_desc,
        mf.physical_name AS filepath,
        mf.size * 8 / 1024.0 AS size_mb,
        CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS INT) * 8 / 1024.0 AS used_space_mb
) dbf
ORDER BY vs.volume_mount_point, dbf.dbname