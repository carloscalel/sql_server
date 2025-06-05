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

EXEC sp_MSforeachdb '
USE [?];
IF DB_ID() NOT IN (1,2,3,4) -- Excluir bases del sistema
BEGIN
    DECLARE @DBName NVARCHAR(128) = DB_NAME();

    SELECT
        @HTML = @HTML + 
        ''<tr>
            <td style="border: 1px solid #ccc; padding: 6px;">'' + @DBName + ''</td>'' +
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' + df.name + ''</td>'' +
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' + LEFT(df.physical_name,1) + ''</td>'' +
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' + df.type_desc + ''</td>'' +

            -- Tamaño
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' + 
                CAST(CAST(df.size * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS NVARCHAR) + ''</td>'' +

            -- Usado
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' + 
                CAST(CAST(FILEPROPERTY(df.name, ''SpaceUsed'') * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS NVARCHAR) + ''</td>'' +

            -- Libre
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' + 
                CAST(CAST((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS NVARCHAR) + ''</td>'' +

            -- % Usado y % Libre
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' +
                CAST(CAST((CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS FLOAT) / df.size) * 100 AS DECIMAL(5,2)) AS NVARCHAR) + ''%</td>'' +
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' +
                CAST(CAST((1 - CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS FLOAT) / df.size) * 100 AS DECIMAL(5,2)) AS NVARCHAR) + ''%</td>'' +

            -- Gráfico de uso
            ''<td style="border: 1px solid #ccc; padding: 6px;">
                <div style="background-color:#eee;width:100%;height:16px;border-radius:4px;">
                    <div style="width:'' + CAST(CAST((CAST(FILEPROPERTY(df.name, ''SpaceUsed'') AS FLOAT) / df.size) * 100 AS INT) AS NVARCHAR) + ''%;
                        background-color:#4caf50;height:100%;border-radius:4px;"></div>
                </div>
            </td>'' +

            -- Sugerencia
            ''<td style="border: 1px solid #ccc; padding: 6px;">'' +
            CASE 
                WHEN df.type_desc = ''ROWS'' AND (df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024 / 1024 > 2 
                THEN ''<span style="color:green;">RECOMENDADO: DBCC SHRINKFILE(['' + df.name + ''], TRUNCATEONLY)</span>''
                ELSE ''<span style="color:gray;">No se recomienda</span>''
            END +
            ''</td>
        </tr>''
    FROM sys.database_files df
    WHERE df.type IN (0,1);
END
'

-- Cierra la tabla
SET @HTML = @HTML + '</table>';

-- Muestra el HTML
PRINT @HTML;
-- SELECT @HTML AS HTML_RESULTADO;
