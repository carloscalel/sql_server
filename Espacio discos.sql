-- Verifica espacio de archivos de bases de datos y sugiere SHRINK, mostrando en MB y GB
EXEC sp_MSforeachdb '
USE [?];
SELECT
    DB_NAME() AS BASE_DATOS,
    df.name AS NOMBRE_ARCHIVO,
    LEFT(df.physical_name, 1) AS DISCO,
    df.physical_name AS RUTA_COMPLETA,
    df.type_desc AS TIPO_ARCHIVO,
    -- Tamaño total
    CAST(df.size * 8.0 / 1024 AS DECIMAL(18,2)) AS TAMANO_MB,
    CAST(df.size * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS TAMANO_GB,
    -- Espacio usado
    CAST(FILEPROPERTY(df.name, ''SpaceUsed'') * 8.0 / 1024 AS DECIMAL(18,2)) AS USADO_MB,
    CAST(FILEPROPERTY(df.name, ''SpaceUsed'') * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS USADO_GB,
    -- Espacio libre
    CAST((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 AS DECIMAL(18,2)) AS LIBRE_MB,
    CAST((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS LIBRE_GB,
    -- Porcentaje de uso
    CAST(CASE WHEN df.size > 0 THEN
        (CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS FLOAT) / CAST(df.size AS FLOAT)) * 100 ELSE 0 END
        AS DECIMAL(5,2)) AS PORCENTAJE_USADO,
    -- Sugerencia de SHRINK
    CASE
        WHEN df.type_desc = ''ROWS''
             AND (df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 > 500
            THEN ''RECOMENDADO: DBCC SHRINKFILE(['' + df.name + ''], TRUNCATEONLY)''
        ELSE ''No se recomienda compactar''
    END AS SUGERENCIA_SHRINK
FROM sys.database_files AS df
WHERE df.type IN (0,1)
ORDER BY BASE_DATOS, DISCO, NOMBRE_ARCHIVO;
'