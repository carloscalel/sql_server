/* ===========================================================
   04_policy_by_table.sql - VERSIÓN FINAL GRANULADA
   1. Limpia permisos previos de los roles de la solución.
   2. Clasifica usuarios:
      - Lectores Totales (db_datareader): Acceso a todo el espejo 'app'.
      - Lectores Granulares: Solo acceso a los objetos que ya tenían.
   3. Aplica DENY quirúrgico para forzar el uso de la máscara.
   ===========================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;

-- 1. Asegurar existencia de roles
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_lectura')     CREATE ROLE [rol_app_lectura];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_bloqueo_dbo') CREATE ROLE [rol_app_bloqueo_dbo];

-- 2. LIMPIEZA INICIAL (RESET)
-- Quitamos permisos previos de estos roles para evitar "basura" de ejecuciones anteriores
DECLARE @SQL_Clean NVARCHAR(MAX) = '';
SELECT @SQL_Clean += 'REVOKE ' + permission_name + ' ON ' + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) + ' FROM [rol_app_lectura]; '
FROM sys.database_permissions p
JOIN sys.objects o ON p.major_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE grantee_principal_id IN (DATABASE_PRINCIPAL_ID('rol_app_lectura'), DATABASE_PRINCIPAL_ID('rol_app_bloqueo_dbo'));

IF LEN(@SQL_Clean) > 0 EXEC sp_executesql @SQL_Clean;

-- 3. CLASIFICACIÓN A: USUARIOS CON ACCESO TOTAL (db_datareader)
-- Les damos acceso a los esquemas 'app' y 'masked' completos.
DECLARE @ReaderUser SYSNAME;
DECLARE curReaders CURSOR FOR 
    SELECT dp.name 
    FROM sys.database_role_members drm
    JOIN sys.database_principals dp ON drm.member_principal_id = dp.principal_id
    WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID('db_datareader')
      AND dp.name NOT IN ('dbo', 'sys');

OPEN curReaders; FETCH NEXT FROM curReaders INTO @ReaderUser;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC('GRANT SELECT ON SCHEMA::app TO [' + @ReaderUser + '];');
    EXEC('GRANT SELECT ON SCHEMA::masked TO [' + @ReaderUser + '];');
    EXEC sp_addrolemember 'rol_app_bloqueo_dbo', @ReaderUser;
    EXEC('ALTER USER [' + @ReaderUser + '] WITH DEFAULT_SCHEMA = app;');
    FETCH NEXT FROM curReaders INTO @ReaderUser;
END
CLOSE curReaders; DEALLOCATE curReaders;

-- 4. CLASIFICACIÓN B: USUARIOS GRANULARES (Tabla por Tabla)
-- Detectamos qué tablas pueden ver actualmente y replicamos el permiso en 'app'
DECLARE @User SYSNAME, @Obj SYSNAME, @Sch SYSNAME;
DECLARE curGranular CURSOR FOR
    SELECT DISTINCT dp.name, o.name, s.name
    FROM sys.database_permissions p
    JOIN sys.objects o ON p.major_id = o.object_id
    JOIN sys.schemas s ON o.schema_id = s.schema_id
    JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
    WHERE p.permission_name = 'SELECT' AND p.state = 'G'
      AND dp.name NOT IN ('dbo', 'db_datareader', 'rol_app_lectura')
      AND o.type = 'U' AND s.name NOT IN ('sys', 'information_schema');

OPEN curGranular; FETCH NEXT FROM curGranular INTO @User, @Obj, @Sch;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Permiso al sinónimo (Puerta de entrada)
    EXEC('GRANT SELECT ON app.' + @Obj + ' TO [' + @User + '];');
    
    -- Si existe vista enmascarada, dar permiso a la vista
    IF EXISTS (SELECT 1 FROM sys.views v JOIN sys.schemas sv ON v.schema_id=sv.schema_id 
               WHERE sv.name = 'masked' AND v.name = @Obj)
    BEGIN
        EXEC('GRANT SELECT ON masked.' + @Obj + ' TO [' + @User + '];');
    END
    
    -- Forzar esquema 'app' y agregar al rol de bloqueo
    EXEC('ALTER USER [' + @User + '] WITH DEFAULT_SCHEMA = app;');
    EXEC sp_addrolemember 'rol_app_bloqueo_dbo', @User;

    FETCH NEXT FROM curGranular INTO @User, @Obj, @Sch;
END
CLOSE curGranular; DEALLOCATE curGranular;

-- 5. BLOQUEO QUIRÚRGICO (DENY)
-- Aplicamos el DENY sobre las tablas reales que tienen versión enmascarada
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
PRINT 'Política aplicada: Granularidad preservada y enmascaramiento forzado.';
