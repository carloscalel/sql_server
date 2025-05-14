DECLARE @linkedServerName SYSNAME = 'LINKED_SERVER' -- Cambia esto por tu servidor vinculado
DECLARE @consultaOriginal NVARCHAR(MAX) = 'SELECT columna1, columna2 FROM nombre_base_de_datos.dbo.nombre_tabla WHERE columna3 = ''valor con comillas''' 
DECLARE @consultaEscapada NVARCHAR(MAX)
DECLARE @sql NVARCHAR(MAX)

-- Reemplazar comillas simples por comillas dobles ('' -> '''') para que funcionen en OPENQUERY
SET @consultaEscapada = REPLACE(@consultaOriginal, '''', '''''')

-- Construir el SQL dinámico para ejecutar vía OPENQUERY
SET @sql = '
SELECT * 
FROM OPENQUERY([' + @linkedServerName + '], ''' + @consultaEscapada + ''')'

-- Ejecutar la consulta
EXEC sp_executesql @sql
