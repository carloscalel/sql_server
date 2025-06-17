DECLARE @UserName SYSNAME = 'usuario_lectura';
DECLARE @SQL NVARCHAR(MAX) = '';

-- Recorremos cada base de datos del sistema (excluyendo las de sistema)
SELECT @SQL = @SQL + '
USE [' + name + '];

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals 
    WHERE name = N''' + @UserName + '''
)
BEGIN
    CREATE USER [' + @UserName + '] FOR LOGIN [' + @UserName + '];
    EXEC sp_addrolemember N''db_datareader'', N''' + @UserName + ''';
    PRINT ''Acceso de lectura otorgado en [' + name + ']'';
END
ELSE
BEGIN
    PRINT ''Usuario ya existe en [' + name + '], no se hizo nada.'';
END;
'
FROM sys.databases
WHERE name NOT IN ('master', 'model', 'msdb', 'tempdb');  -- Opcional: excluir bases del sistema

-- Ejecutamos el código generado
EXEC sp_executesql @SQL;