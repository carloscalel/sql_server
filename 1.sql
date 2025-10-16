/****************************************************************************************
 Script:       00_setup_masking_framework.sql
 Descripción:  Inicializa el framework de enmascaramiento automático.
               Crea esquemas, tablas base, bitácora y carga patrones de búsqueda.

 Versión:      3.1
****************************************************************************************/

PRINT '============================================================';
PRINT ' INICIALIZANDO FRAMEWORK DE ENMASCARAMIENTO (v3.1)';
PRINT '============================================================';

------------------------------------------------------------
-- 1. CREAR ESQUEMAS BASE
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'masked')
    EXEC('CREATE SCHEMA masked;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'app')
    EXEC('CREATE SCHEMA app;');

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
END

------------------------------------------------------------
-- 3. TABLA DE PATRONES (estructura original)
------------------------------------------------------------
IF OBJECT_ID('masked.Masked_Patterns') IS NULL
BEGIN
    CREATE TABLE masked.Masked_Patterns (
        Id INT IDENTITY PRIMARY KEY,
        Pattern NVARCHAR(100),
        DDMFunction NVARCHAR(200),
        ViewMaskExpr NVARCHAR(400),
        Activo BIT DEFAULT 1,
        FechaRegistro DATETIME DEFAULT GETDATE()
    );
END

------------------------------------------------------------
-- 4. TABLA DE CONTROL DE TABLAS ENMASCARADAS
------------------------------------------------------------
IF OBJECT_ID('masked.Tablas_Control') IS NULL
BEGIN
    CREATE TABLE masked.Tablas_Control (
        Id INT IDENTITY PRIMARY KEY,
        Esquema NVARCHAR(128),
        Tabla NVARCHAR(128),
        TipoAplicacion NVARCHAR(50), -- DIRECTO o VISTA
        Fecha DATETIME DEFAULT GETDATE(),
        UsuarioEjecutor NVARCHAR(128) DEFAULT ORIGINAL_LOGIN()
    );
END

------------------------------------------------------------
-- 5. CARGAR PATRONES PERSONALIZADOS
------------------------------------------------------------
DELETE FROM masked.Masked_Patterns;

INSERT INTO masked.Masked_Patterns (Pattern, DDMFunction, ViewMaskExpr)
VALUES
('TARJETA','partial(0,"XXXXXXXXXXXXXXX",4)','LEFT({col},0)+REPLICATE(''X'',15)+RIGHT({col},4)'),
('CUENTA','partial(0,"XXXXXXXXXXXX",4)','LEFT({col},0)+REPLICATE(''X'',12)+RIGHT({col},4)'),
('CODIGO','partial(6,"XXXXXX",4)','LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
('AUTENTICACION','partial(6,"XXXXXX",4)','LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
('MAGNETICA','partial(6,"XXXXXX",4)','LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
('CV2','partial(6,"XXXXXX",4)','LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
('CVV2','partial(6,"XXXXXX",4)','LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
('BIN','partial(6,"XXXXXX",4)','LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
('FECHA_V','default()','CONVERT(CHAR(10),GETDATE(),120)'),
('NOM_','partial(10,"XXXXXXXXXXXXXXXXXXXX",0)','LEFT({col},10)+REPLICATE(''X'',20)'),
('EMAIL','email()','CONCAT(LEFT({col},2),''*****@masked.com'')'),
('NACIMIENTO','default()','NULL'),
('BLOQUEO','default()','NULL'),
('TOKEN','default()','NULL'),
('NIT','default()','NULL'),
('DIRECCION','default()','''DIRECCION ENMASCARADA'''),
('DIR_','default()','''DIRECCION ENMASCARADA'''),
('TEL','default()','''0000-0000'''),
('TELEFONO','default()','''0000-0000''');

------------------------------------------------------------
-- 6. MENSAJE FINAL
------------------------------------------------------------
PRINT '============================================================';
PRINT ' FRAMEWORK DE ENMASCARAMIENTO CONFIGURADO CORRECTAMENTE';
PRINT '============================================================';
GO