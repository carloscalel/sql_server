SELECT 
    DB_NAME(mf.database_id) AS BaseDeDatos,
    mf.type_desc AS TipoArchivo,
    mf.physical_name AS RutaArchivo,
    CONVERT(DECIMAL(18,2), mf.size * 8.0 / 1024) AS TamañoAsignado_MB,
    CONVERT(DECIMAL(18,2), CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS INT) * 8.0 / 1024) AS EspacioUsado_MB,
    CONVERT(DECIMAL(18,2), (mf.size * 8.0 / 1024) - (CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS INT) * 8.0 / 1024)) AS PorCompactar_MB
FROM sys.master_files mf
ORDER BY BaseDeDatos, TipoArchivo