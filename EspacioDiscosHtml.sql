-- Elimina tabla temporal si existe
IF OBJECT_ID('tempdb..#EspacioDB') IS NOT NULL DROP TABLE #EspacioDB;

-- Crea tabla temporal SIN columnas calculadas
CREATE TABLE #EspacioDB (
    BASE_DATOS NVARCHAR(128),
    NOMBRE_ARCHIVO NVARCHAR(128),
    DISCO CHAR(1),
    TIPO NVARCHAR(60),
    TAMANO_GB DECIMAL(10,2),
    USADO_GB DECIMAL(10,2),
    LIBRE_GB DECIMAL(10,2),
    PORC_USADO DECIMAL(5,2),
    PORC_LIBRE DECIMAL(5,2),
    SUGERENCIA NVARCHAR(MAX)
);

-- Ejecuta por cada base de datos
EXEC sp_MSforeachdb '
USE [?];
IF DB_ID() NOT IN (1,2,3,4) -- Excluir bases de sistema
BEGIN
    INSERT INTO #EspacioDB (
        BASE_DATOS, NOMBRE_ARCHIVO, DISCO, TIPO, TAMANO_GB, USADO_GB, LIBRE_GB, PORC_USADO, PORC_LIBRE, SUGERENCIA
    )
    SELECT
        DB_NAME(),
        df.name,
        LEFT(df.physical_name, 1),
        df.type_desc,
        CAST(df.size * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS TAMANO_GB,
        CAST(FILEPROPERTY(df.name, ''SpaceUsed'') * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS USADO_GB,
        CAST((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS LIBRE_GB,
        CAST(
            CASE WHEN df.size > 0 THEN
                (CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS FLOAT) / df.size) * 100
            ELSE 0 END
        AS DECIMAL(5,2)) AS PORC_USADO,
        CAST(
            CASE WHEN df.size > 0 THEN
                (1 - (CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS FLOAT) / df.size)) * 100
            ELSE 0 END
        AS DECIMAL(5,2)) AS PORC_LIBRE,
        CASE 
            WHEN df.type_desc = ''ROWS'' AND (df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 / 1024 > 2
                THEN ''RECOMENDADO: DBCC SHRINKFILE(['' + df.name + ''], TRUNCATEONLY)''
            ELSE ''No se recomienda''
        END AS SUGERENCIA
    FROM sys.database_files df
    WHERE df.type IN (0,1);
END
';

-- Aquí podrías usar SELECT * FROM #EspacioDB para revisar los resultados.

-- Genera HTML
DECLARE @HTML NVARCHAR(MAX) = '';

SET @HTML = '
<h2>📊 Reporte Semanal de Espacio por Base de Datos</h2>
<table style="font-family: Arial; border-collapse: collapse; width: 100%;">
<tr style="background-color: #f2f2f2;">
    <th style="border: 1px solid #ccc; padding: 6px;">BASE_DATOS</th>
    <th style="border: 1px solid #ccc; padding: 6px;">NOMBRE_ARCHIVO</th>
    <th style="border: 1px solid #ccc; padding: 6px;">DISCO</th>
    <th style="border: 1px solid #ccc; padding: 6px;">TIPO</th>
    <th style="border: 1px solid #ccc; padding: 6px;">TAMANO_GB</th>
    <th style="border: 1px solid #ccc; padding: 6px;">USADO_GB</th>
    <th style="border: 1px solid #ccc; padding: 6px;">LIBRE_GB</th>
    <th style="border: 1px solid #ccc; padding: 6px;">% USADO</th>
    <th style="border: 1px solid #ccc; padding: 6px;">% LIBRE</th>
    <th style="border: 1px solid #ccc; padding: 6px;">Gráfico de Uso</th>
    <th style="border: 1px solid #ccc; padding: 6px;">SUGERENCIA</th>
</tr>
';

-- Leer los datos desde la tabla temporal
DECLARE @DB NVARCHAR(128), @File NVARCHAR(128), @Disk CHAR(1), @Tipo NVARCHAR(60)
DECLARE @Tamano DECIMAL(10,2), @Usado DECIMAL(10,2), @Libre DECIMAL(10,2), @PU DECIMAL(5,2), @PL DECIMAL(5,2)
DECLARE @Sug NVARCHAR(MAX)

DECLARE cur CURSOR FOR 
    SELECT BASE_DATOS, NOMBRE_ARCHIVO, DISCO, TIPO, TAMANO_GB, USADO_GB, LIBRE_GB, PORC_USADO, PORC_LIBRE, SUGERENCIA
    FROM #EspacioDB;

OPEN cur;
FETCH NEXT FROM cur INTO @DB, @File, @Disk, @Tipo, @Tamano, @Usado, @Libre, @PU, @PL, @Sug;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @HTML += '
    <tr>
        <td style="border:1px solid #ccc;padding:6px;">' + @DB + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + @File + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + @Disk + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + @Tipo + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + CAST(@Tamano AS NVARCHAR) + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + CAST(@Usado AS NVARCHAR) + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + CAST(@Libre AS NVARCHAR) + '</td>
        <td style="border:1px solid #ccc;padding:6px;">' + CAST(@PU AS NVARCHAR) + '%</td>
        <td style="border:1px solid #ccc;padding:6px;">' + CAST(@PL AS NVARCHAR) + '%</td>
        <td style="border:1px solid #ccc;padding:6px;">
            <div style="background-color:#eee;width:100%;height:16px;border-radius:4px;">
                <div style="width:' + CAST(CAST(@PU AS INT) AS NVARCHAR) + '%;background-color:#4caf50;height:100%;border-radius:4px;"></div>
            </div>
        </td>
        <td style="border:1px solid #ccc;padding:6px;">' + @Sug + '</td>
    </tr>';

    FETCH NEXT FROM cur INTO @DB, @File, @Disk, @Tipo, @Tamano, @Usado, @Libre, @PU, @PL, @Sug;
END
CLOSE cur; DEALLOCATE cur;

-- Finaliza tabla HTML
SET @HTML += '</table>';

-- Muestra resultado
SELECT @HTML AS Reporte_HTML;
