-- Esperar a que la BD esté en línea
DECLARE @dbname SYSNAME = N'TuBD';
DECLARE @sql NVARCHAR(MAX);

-- Espera activa hasta que la BD esté ONLINE
WHILE EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE name = @dbname AND state_desc <> 'ONLINE'
)
BEGIN
    WAITFOR DELAY '00:00:05'; -- espera 5 segundos
END;

-- Crear usuario si no existe
SET @sql = N'
USE [' + @dbname + '];

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''usuario_app'')
BEGIN
    CREATE USER [usuario_app] FOR LOGIN [usuario_app];
    EXEC sp_addrolemember ''db_datareader'', ''usuario_app'';  -- permisos mínimos
    -- Si necesita escritura:
    -- EXEC sp_addrolemember ''db_datawriter'', ''usuario_app'';
    PRINT ''Usuario [usuario_app] creado y asignado correctamente en [' + @dbname + ']'';
END
ELSE
BEGIN
    PRINT ''Usuario [usuario_app] ya existe en [' + @dbname + ']'';
END
';

EXEC sp_executesql @sql;