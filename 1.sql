/* ===========================================================
   04_policy_by_table.sql - VERSIÓN FINAL GRANULADA & SEGURA
   1. Define usuarios excluidos (SysAdmin, DB_Owners, etc.)
   2. Limpia permisos previos de los roles de la solución.
   3. Clasifica usuarios y replica accesos existentes.
   4. Bloquea tablas reales y fuerza esquema 'app'.
   ===========================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;

-- 1. CONFIGURACIÓN DE EXCLUSIONES
IF OBJECT_ID('tempdb..#Excluidos') IS NOT NULL DROP TABLE #Excluidos;
CREATE TABLE #Excluidos (UserName SYSNAME PRIMARY KEY);

-- Agrega aquí todas las cuentas que NO deben ser tocadas por el enmascaramiento
INSERT INTO #Excluidos VALUES 
(N'svc_replicacion'), 
(N'db_owner'), 
(N'sa'),
(N'administrador_db'); -- Agrega los que necesites

-- 2. ASEGURAR ROLES E INFRAESTRUCTURA
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_lectura')     CREATE ROLE [rol_app_lectura];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_bloqueo_dbo') CREATE ROLE [rol_app_bloqueo_dbo];

-- Limpieza de permisos previos en los roles para evitar conflictos
DECLARE @SQL_Clean NVARCHAR(MAX) = '';
SELECT @SQL_Clean += 'REVOKE ' + permission_name + ' ON ' + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) + ' FROM [rol_app_lectura]; '
FROM sys.database_permissions p
JOIN sys.objects o ON p.major_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE grantee_principal_id IN (DATABASE_PRINCIPAL_ID('rol_app_lectura'), DATABASE_PRINCIPAL_ID('rol_app_bloqueo_dbo'));

IF LEN(@SQL_Clean) > 0 EXEC sp_executesql @SQL_Clean;

-- 3. CLASIFICACIÓN A: USUARIOS CON ACCESO TOTAL (db_datareader)
DECLARE @ReaderUser SYSNAME;
DECLARE curReaders CURSOR FOR 
    SELECT dp.name 
    FROM sys.database_role_members drm
    JOIN sys.database_principals dp ON drm.member_principal_id = dp.principal_id
    LEFT JOIN #Excluidos ex ON ex.UserName = dp.name
    WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID('db_datareader')
      AND dp.name NOT IN ('dbo', 'sys', 'INFORMATION_SCHEMA')
      AND ex.UserName IS NULL; -- Solo procesar si no está excluido

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

-- 4. CLASIFICACIÓN B: USUARIOS GRANULARES (Heredar accesos previos)
DECLARE @User SYSNAME, @Obj SYSNAME, @Sch SYSNAME;
DECLARE curGranular CURSOR FOR
    SELECT DISTINCT dp.name, o.name, s.name
    FROM sys.database_permissions p
    JOIN sys.objects o ON p.major_id = o.object_id
    JOIN sys.schemas s ON o.schema_id = s.schema_id
    JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
    LEFT JOIN #Excluidos ex ON ex.UserName = dp.name
    WHERE p.permission_name = 'SELECT' AND p.state = 'G'
      AND dp.name NOT IN ('dbo', 'db_datareader', 'rol_app_lectura')
      AND o.type = 'U' AND s.name NOT IN ('sys', 'information_schema', 'app', 'masked')
      AND ex.UserName IS NULL; -- Solo procesar si no está excluido

OPEN curGranular; FETCH NEXT FROM curGranular INTO @User, @Obj, @Sch;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Replicamos el permiso al sinónimo (app) para mantener la granularidad
    IF EXISTS (SELECT 1 FROM sys.synonyms WHERE name = @Obj AND schema_id = SCHEMA_ID('app'))
        EXEC('GRANT SELECT ON app.' + @Obj + ' TO [' + @User + '];');
    
    -- Si existe vista enmascarada, dar permiso a la máscara
    IF EXISTS (SELECT 1 FROM sys.views v JOIN sys.schemas sv ON v.schema_id=sv.schema_id 
               WHERE sv.name = 'masked' AND v.name = @Obj)
        EXEC('GRANT SELECT ON masked.' + @Obj + ' TO [' + @User + '];');
    
    EXEC('ALTER USER [' + @User + '] WITH DEFAULT_SCHEMA = app;');
    EXEC sp_addrolemember 'rol_app_bloqueo_dbo', @User;

    FETCH NEXT FROM curGranular INTO @User, @Obj, @Sch;
END
CLOSE curGranular; DEALLOCATE curGranular;

-- 5. APLICACIÓN DEL DENY (Bloqueo de tablas reales)
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

PRINT 'Limpieza, clasificación y política aplicadas con éxito.';
