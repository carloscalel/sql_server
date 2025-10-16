/****************************************************************************************
 Script:       00_setup_masking_framework.sql
 Descripción:  Inicializa el framework de enmascaramiento automático.
               Crea los esquemas, tablas de metadatos y registra patrones sensibles.

 Versión:      3.0
 Autor:        Framework SQL Masking (ChatGPT)
****************************************************************************************/

PRINT '============================================================';
PRINT ' INICIALIZANDO FRAMEWORK DE ENMASCARAMIENTO (v3.0)';
PRINT '============================================================';
PRINT '';

------------------------------------------------------------
-- 1. CREAR ESQUEMAS BASE
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'masked')
BEGIN
    EXEC('CREATE SCHEMA masked;');
    PRINT '>> Esquema [masked] creado.';
END
ELSE
    PRINT '>> Esquema [masked] ya existe.';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'app')
BEGIN
    EXEC('CREATE SCHEMA app;');
    PRINT '>> Esquema [app] creado.';
END
ELSE
    PRINT '>> Esquema [app] ya existe.';

------------------------------------------------------------
-- 2. TABLA DE BITÁCORA
------------------------------------------------------------
IF OBJECT_ID('masked.Bitacora_Masking') IS NULL
BEGIN
    CREATE TABLE masked.Bitacora_Masking (
        Id INT IDENTITY PRIMARY KEY,
        Fecha DATETIME DEFAULT GETDATE(),
        Tabla NVARCHAR(128),
        Columna NVARCHAR(128),
        TipoOperacion NVARCHAR(50),
        UsuarioEjecutor NVARCHAR(128) DEFAULT ORIGINAL_LOGIN(),
        Detalle NVARCHAR(MAX)
    );
    PRINT '>> Tabla [masked.Bitacora_Masking] creada.';
END
ELSE
    PRINT '>> Tabla [masked.Bitacora_Masking] ya existe.';


------------------------------------------------------------
-- 3. TABLA DE PATRONES
------------------------------------------------------------
IF OBJECT_ID('masked.Patrones_Masking') IS NULL
BEGIN
    CREATE TABLE masked.Patrones_Masking (
        Id INT IDENTITY PRIMARY KEY,
        Patron NVARCHAR(100) NOT NULL,
        Metodo NVARCHAR(200) NOT NULL,
        Activo BIT DEFAULT 1,
        FechaRegistro DATETIME DEFAULT GETDATE()
    );
    PRINT '>> Tabla [masked.Patrones_Masking] creada.';
END
ELSE
    PRINT '>> Tabla [masked.Patrones_Masking] ya existe.';


------------------------------------------------------------
-- 4. TABLA DE CONTROL DE TABLAS ENMASCARADAS
------------------------------------------------------------
IF OBJECT_ID('masked.Tablas_Control') IS NULL
BEGIN
    CREATE TABLE masked.Tablas_Control (
        Id INT IDENTITY PRIMARY KEY,
        Esquema NVARCHAR(128),
        Tabla NVARCHAR(128),
        TipoAplicacion NVARCHAR(50),  -- DIRECTO o VISTA
        Fecha DATETIME DEFAULT GETDATE(),
        UsuarioEjecutor NVARCHAR(128) DEFAULT ORIGINAL_LOGIN()
    );
    PRINT '>> Tabla [masked.Tablas_Control] creada.';
END
ELSE
    PRINT '>> Tabla [masked.Tablas_Control] ya existe.';


------------------------------------------------------------
-- 5. INSERTAR PATRONES DE ENMASCARAMIENTO
------------------------------------------------------------
PRINT 'Insertando patrones predefinidos...';

DELETE FROM masked.Patrones_Masking;

INSERT INTO masked.Patrones_Masking (Patron, Metodo)
VALUES
('TARJETA','partial(0,"XXXXXXXXXXXXXXX",4)'),
('CUENTA','partial(0,"XXXXXXXXXXXX",4)'),
('CODIGO','partial(6,"XXXXXX",4)'),
('AUTENTICACION','partial(6,"XXXXXX",4)'),
('MAGNETICA','partial(6,"XXXXXX",4)'),
('CV2','partial(6,"XXXXXX",4)'),
('CVV2','partial(6,"XXXXXX",4)'),
-- ('CID','partial(6,"XXXXXX",4)'),  -- Omitido según tu preferencia
('BIN','partial(6,"XXXXXX",4)'),
('FECHA_V','default()'),
('NOM_','partial(10,"XXXXXXXXXXXXXXXXXXXX",0)'),
('EMAIL','email()'),
('NACIMIENTO','default()'),
('BLOQUEO','default()'),
('TOKEN','default()'),
('NIT','default()'),
('DIRECCION','default()'),
('DIR_','default()'),
('TEL','default()'),
('TELEFONO','default()');

PRINT '>> Patrones insertados correctamente.';
PRINT '';

------------------------------------------------------------
-- 6. MENSAJE FINAL
------------------------------------------------------------
PRINT '============================================================';
PRINT ' FRAMEWORK DE ENMASCARAMIENTO CONFIGURADO CORRECTAMENTE';
PRINT ' Esquemas creados: [masked], [app]';
PRINT ' Tablas: Bitacora_Masking, Patrones_Masking, Tablas_Control';
PRINT '============================================================';
GO