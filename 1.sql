/* ===========================================================
   ROLLBACK DE SEGURIDAD - RESTAURACIÓN DE ROLES NATIVOS
   ===========================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;

PRINT 'Iniciando restauración de permisos originales...';

-- 1. IDENTIFICAR Y MOVER USUARIOS DE VUELTA A ROLES NATIVOS
-- Recorremos a los miembros de nuestros roles para devolverles su estatus
DECLARE @Usuario SYSNAME, @SqlRestaurar NVARCHAR(MAX);

-- Cursor para usuarios que estaban en el esquema de lectura de la solución
DECLARE curRestaurar CURSOR FOR 
    SELECT dp.name 
    FROM sys.database_role_members drm
    JOIN sys.database_principals dp ON drm.member_principal_id = dp.principal_id
    WHERE drm.role_principal_id IN (DATABASE_PRINCIPAL_ID('rol_app_lectura'), DATABASE_PRINCIPAL_ID('rol_app_bloqueo_dbo'));

OPEN curRestaurar; FETCH NEXT FROM curRestaurar INTO @Usuario;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        -- A. Devolver a db_datareader
        EXEC sp_addrolemember 'db_datareader', @Usuario;
        
        -- B. Si el usuario estaba en un rol de DML/Escritura (opcional según tu lógica)
        -- Si usaste 'rol_app_dml', lo devolvemos a db_datawriter
        IF IS_ROLEMEMBER('rol_app_dml', @Usuario) = 1 OR IS_ROLEMEMBER('rol_app_escritura', @Usuario) = 1
            EXEC sp_addrolemember 'db_datawriter', @Usuario;

        -- C. Regresar el esquema por defecto a dbo
        EXEC('ALTER USER [' + @Usuario + '] WITH DEFAULT_SCHEMA = dbo;');
        
        PRINT 'Usuario [' + @Usuario + '] restaurado a db_datareader y esquema dbo.';
    END TRY
    BEGIN CATCH
        PRINT 'Error restaurando usuario [' + @Usuario + ']: ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM curRestaurar INTO @Usuario;
END
CLOSE curRestaurar; DEALLOCATE curRestaurar;

-- 2. LIMPIEZA DE LA CAPA DE ABSTRACCIÓN (Sinónimos y Vistas)
-- (Usamos el mismo código de limpieza anterior para borrar app.* y masked.*)
PRINT 'Limpiando sinónimos y vistas...';
DECLARE @ObjName SYSNAME, @SchemaName SYSNAME, @DropSql NVARCHAR(MAX);

DECLARE curLimpiar CURSOR FOR 
    SELECT s.name, o.name FROM sys.objects o JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name IN ('app', 'masked') AND o.type IN ('SN', 'V');

OPEN curLimpiar; FETCH NEXT FROM curLimpiar INTO @SchemaName, @ObjName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @DropSql = 'DROP ' + (CASE WHEN EXISTS(SELECT 1 FROM sys.synonyms WHERE name=@ObjName AND schema_id=SCHEMA_ID(@SchemaName)) THEN 'SYNONYM ' ELSE 'VIEW ' END) 
                 + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjName);
    EXEC sp_executesql @DropSql;
    FETCH NEXT FROM curLimpiar INTO @SchemaName, @ObjName;
END
CLOSE curLimpiar; DEALLOCATE curLimpiar;

-- 3. VACIAR Y ELIMINAR LOS ROLES DE LA SOLUCIÓN
-- Ahora que ya los movimos, podemos borrar los roles sin el error de "has members"
DECLARE @RoleName SYSNAME;
DECLARE curRoles CURSOR FOR SELECT name FROM sys.database_principals WHERE name IN ('rol_app_lectura', 'rol_app_bloqueo_dbo', 'rol_app_dml') AND type = 'R';

OPEN curRoles; FETCH NEXT FROM curRoles INTO @RoleName;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Sacar a todos los miembros restantes por seguridad
    DECLARE @Member SYSNAME;
    DECLARE curM CURSOR FOR SELECT dp.name FROM sys.database_role_members drm JOIN sys.database_principals dp ON drm.member_principal_id = dp.principal_id WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(@RoleName);
    OPEN curM; FETCH NEXT FROM curM INTO @Member;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC('ALTER ROLE ' + QUOTENAME(@RoleName) + ' DROP MEMBER ' + QUOTENAME(@Member));
        FETCH NEXT FROM curM INTO @Member;
    END
    CLOSE curM; DEALLOCATE curM;

    EXEC('DROP ROLE ' + QUOTENAME(@RoleName));
    PRINT 'Rol [' + @RoleName + '] eliminado.';
    FETCH NEXT FROM curRoles INTO @RoleName;
END
CLOSE curRoles; DEALLOCATE curRoles;

PRINT 'Rollback finalizado con éxito.';
