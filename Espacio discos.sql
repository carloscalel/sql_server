-- Verifica espacio de archivos de bases de datos y sugiere SHRINK
USE master;
GO

SELECT
    DB_NAME(mf.database_id) AS BASE_DATOS,
    mf.name AS NOMBRE_ARCHIVO,
    LEFT(mf.physical_name, 1) AS DISCO,
    mf.physical_name AS RUTA_COMPLETA,
    mf.type_desc AS TIPO_ARCHIVO,
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS TAMANO_MB,
    CAST(mf.size * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS TAMANO_GB,
    CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(18,2)) AS USADO_MB,
    CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS USADO_GB,
    CAST((mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(18,2)) AS LIBRE_MB,
    CAST((mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS LIBRE_GB,
    CAST(CASE WHEN mf.size > 0 THEN
        (CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS FLOAT) / CAST(mf.size AS FLOAT)) * 100 ELSE 0 END
        AS DECIMAL(5,2)) AS PORCENTAJE_USADO,
    CASE
        WHEN mf.type_desc = 'ROWS' AND (mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 8.0 / 1024 > 500
            THEN 'RECOMENDADO: DBCC SHRINKFILE([' + mf.name + '], TRUNCATEONLY)'
        ELSE 'No se recomienda compactar'
    END AS SUGERENCIA_SHRINK
FROM sys.master_files AS mf
WHERE mf.type IN (0,1) -- 0: Data, 1: Log
ORDER BY BASE_DATOS, DISCO, NOMBRE_ARCHIVO;