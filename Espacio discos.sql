-- VERIFICA ESPACIOS / UBICACIONES DE ARCHIVOS DE BASES DE DATOS Y SUGIERE SHRINK
EXEC sp_MSforeachdb '
USE [?];
SELECT
    DB_NAME() AS BASE_DATOS,
    df.name AS NOMBRE_ARCHIVO,
    LEFT(df.physical_name, 1) AS DISCO,
    df.physical_name AS RUTA_COMPLETA,
    df.type_desc AS TIPO_ARCHIVO,
    df.size / 128.0 AS TAMANIO_MB,
    CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS INT) / 128.0 AS ESPACIO_USADO_MB,
    df.size / 128.0 - CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS INT) / 128.0 AS ESPACIO_LIBRE_MB,
    CASE 
        WHEN df.type_desc = ''ROWS'' THEN df.size / 128.0 - CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS INT) / 128.0
        ELSE 0 
    END AS ESPACIO_COMPACTABLE_MB,
    CASE 
        WHEN df.type_desc = ''ROWS'' 
             AND (df.size / 128.0 - CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS INT) / 128.0) > 500
        THEN ''-- RECOMENDADO: DBCC SHRINKFILE(['' + df.name + ''], TRUNCATEONLY)''
        ELSE ''-- No se recomienda compactar''
    END AS SUGERENCIA_SHRINK
FROM sys.database_files AS df
WHERE df.type IN (0, 1);
';