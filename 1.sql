/* ===========================================================
   04_policy_by_table_v2.sql - CONTROL GRANULADO
   ===========================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;

-- 1. Asegurar que los roles existan
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_lectura')     CREATE ROLE rol_app_lectura;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_bloqueo_dbo') CREATE ROLE rol_app_bloqueo_dbo;

-- 2. ACCESO GENERAL (Para no dejar tablas fuera)
-- Damos permiso de lectura a los esquemas de negocio para que las tablas "no tocadas" funcionen.
DECLARE @schName SYSNAME;
DECLARE curSch CURSOR FOR 
    SELECT name FROM sys.schemas 
    WHERE name NOT IN ('sys', 'INFORMATION_SCHEMA', 'masked', 'app');
OPEN curSch; FETCH NEXT FROM curSch INTO @schName;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC('GRANT SELECT ON SCHEMA::' + @schName + ' TO rol_app_lectura;');
    FETCH NEXT FROM curSch INTO @schName;
END
CLOSE curSch; DEALLOCATE curSch;

-- 3. ACCESO A LA CAPA DE MÁSCARA
GRANT SELECT ON SCHEMA::app TO rol_app_lectura;
GRANT SELECT ON SCHEMA::masked TO rol_app_lectura;

-- 4. BLOQUEO QUIRÚRGICO (Granulado por objeto)
-- Solo denegamos el acceso a las tablas ORIGINALES que tienen una vista en 'masked'
DECLARE @denySql NVARCHAR(MAX) = '';
SELECT @denySql += N'DENY SELECT ON ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + N' TO rol_app_bloqueo_dbo; '
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE EXISTS (
    SELECT 1 FROM sys.views v 
    JOIN sys.schemas sv ON sv.schema_id = v.schema_id 
    WHERE sv.name = 'masked' AND v.name = t.name
);

IF LEN(@denySql) > 0 EXEC sp_executesql @denySql;

-- 5. ONBOARDING DE USUARIOS
-- (Mantenemos tu lógica de cursor pero asegurando los roles correctos)
/*
   EXEC sp_addrolemember 'rol_app_lectura', @u;
   EXEC sp_addrolemember 'rol_app_bloqueo_dbo', @u;
   EXEC('ALTER USER ['+@u+'] WITH DEFAULT_SCHEMA = app;');
*/
