DECLARE @dbname SYSNAME;
DECLARE db_cursor CURSOR FOR
SELECT name FROM sys.databases
WHERE name LIKE 'TuBD%';  -- o ajusta el filtro a tus BDs restauradas

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sql NVARCHAR(MAX) = '
    USE [' + @dbname + '];
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''usuario_app'')
    BEGIN
        CREATE USER [usuario_app] FOR LOGIN [usuario_app];
        EXEC sp_addrolemember ''db_datareader'', ''usuario_app'';
        PRINT ''Usuario creado en [' + @dbname + ']'';
    END';
    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_cursor INTO @dbname;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;