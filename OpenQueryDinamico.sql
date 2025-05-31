DECLARE @ServerCollation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;  -- Cambiar por el nombre real del Linked Server

DECLARE @SQL NVARCHAR(MAX) = N'';

-- Construimos la consulta SQL
SET @SQL += N'

';

-- Remplazamos las comillas simples duplicándolas
SET @SQL = REPLACE(@SQL, '''', '''''');

-- Construimos el OPENQUERY con la consulta SQL y encerrado entre comillas simples
DECLARE @OpenquerySQL NVARCHAR(MAX);
SET @OpenquerySQL = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@ServerName) + N', ''' + @SQL + N''')';

-- Ejecutamos el SQL dinámico
PRINT @OpenquerySQL
EXEC (@OpenquerySQL);

--PRINT @OpenquerySQL

