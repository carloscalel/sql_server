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
    CAST((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 AS DECIMAL(18,2)) AS LIBRE