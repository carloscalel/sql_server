IF OBJECT_ID('tempdb..#Resultados') IS NOT NULL
    DROP TABLE #Resultados;

CREATE TABLE #Resultados (
    BaseDeDatos SYSNAME,
    NombreArchivo SYSNAME,
    Disco NVARCHAR(10),
    RutaCompleta NVARCHAR(MAX),
    TipoArchivo NVARCHAR(20),
    Tamaño_Total_MB DECIMAL(18,2),
    Espacio_Usado_MB DECIMAL(18,2),
    Espacio_Libre_MB DECIMAL(18,2),
    Espacio_Compactable_MB DECIMAL(18,2),
    Sugerencia_SHRINK NVARCHAR(5)
);

DECLARE @sql NVARCHAR(MAX);

-- Recorremos todas las bases de datos que están ONLINE y no son TEMPDB
DECLARE db_cursor CURSOR FOR
SELECT name 
FROM sys.databases 
WHERE state_desc = 'ONLINE' AND database_id <> 2;

DECLARE @dbname SYSNAME;
OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = '
    USE [' + QUOTENAME(@dbname) + '];

    INSERT INTO #Resultados
    SELECT 
        DB_NAME() AS BaseDeDatos,
        mf.name AS NombreArchivo,
        LEFT(mf.physical_name, 2) AS Disco,
        mf.physical_name AS RutaCompleta,
        mf.type_desc AS TipoArchivo,
        CAST(mf.size * 8 / 1024 AS DECIMAL(18,2)) AS Tamaño_Total_MB,
        CAST(FILEPROPERTY(mf.name, ''SpaceUsed'') * 8 / 1024 AS DECIMAL(18,2)) AS Espacio_Usado_MB,
        CAST((mf.size - FILEPROPERTY(mf.name, ''SpaceUsed'')) * 8 / 1024 AS DECIMAL(18,2)) AS Espacio_Libre_MB,
        CAST((mf.size - FILEPROPERTY(mf.name, ''SpaceUsed'')) * 8 / 1024 AS DECIMAL(18,2)) AS Espacio_Compactable_MB,
        CASE 
            WHEN mf.size > 0 AND 
                 (CAST(mf.size - FILEPROPERTY(mf.name, ''SpaceUsed'') AS FLOAT) / mf.size) > 0.3 
            THEN ''SÍ''
            ELSE ''NO''
        END AS Sugerencia_SHRINK
    FROM sys.database_files mf;
    ';
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @dbname;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Mostrar los resultados
SELECT * FROM #Resultados
ORDER BY Disco, BaseDeDatos, TipoArchivo;