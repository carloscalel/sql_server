/* =========================================
  Framework de enmascaramiento (v3 con SINÓNIMOS + patrones ampliados)
  - Crea esquemas: masked (vistas) y app (sinónimos)
  - Crea roles
  - Endurece acceso a dbo para PUBLIC
  - Bitácora y tabla de patrones extendida
  Compatibilidad: SQL Server 2016+
=========================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;

-- Esquemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'masked')
  EXEC('CREATE SCHEMA [masked] AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'app')
  EXEC('CREATE SCHEMA [app] AUTHORIZATION dbo;');  -- aquí irán los sinónimos

-- Roles
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_app_lectura' AND type='R')
  EXEC('CREATE ROLE [rol_app_lectura];');
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'rol_admin_datos' AND type='R')
  EXEC('CREATE ROLE [rol_admin_datos];');

-- Bitácora
IF OBJECT_ID('dbo.Masked_Audit','U') IS NULL
BEGIN
  CREATE TABLE dbo.Masked_Audit(
    AuditId     INT IDENTITY(1,1) PRIMARY KEY,
    EventDate   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ObjectType  NVARCHAR(20) NOT NULL,   -- DDM | VIEW | TRIGGER | SECURITY | SYNONYM | ERROR
    SchemaName  SYSNAME NULL,
    ObjectName  SYSNAME NULL,
    ColumnName  SYSNAME NULL,
    Action      NVARCHAR(200) NOT NULL,
    Details     NVARCHAR(MAX) NULL
  );
END

-- Tabla de patrones (configurable)
IF OBJECT_ID('dbo.Masked_Patterns','U') IS NULL
BEGIN
  CREATE TABLE dbo.Masked_Patterns(
    Pattern       NVARCHAR(100) NOT NULL PRIMARY KEY,  -- LIKE sobre nombre de columna
    DdmFunction   SYSNAME       NOT NULL,              -- 'email()' | 'default()' | 'partial(...)' | 'random(1,9)'
    ViewMaskExpr  NVARCHAR(4000) NOT NULL              -- Expresión para vistas (usar {col} como placeholder)
  );
END
ELSE
BEGIN
  -- Limpieza parcial solo si se desea recargar
  DELETE FROM dbo.Masked_Patterns;
END

-- Insertar patrones base + ampliados
INSERT INTO dbo.Masked_Patterns(Pattern,DdmFunction,ViewMaskExpr) VALUES
-- ====== PATRONES CLÁSICOS BASE ======
(N'%email%',    N'email()', N'CASE WHEN CHARINDEX(''@'',{col})>1 THEN STUFF({col},2,CHARINDEX(''@'',{col})-2,REPLICATE(''x'',CASE WHEN CHARINDEX(''@'',{col})-2<0 THEN 0 ELSE CHARINDEX(''@'',{col})-2 END)) ELSE ''x@x.x'' END'),
(N'%correo%',   N'email()', N'CASE WHEN CHARINDEX(''@'',{col})>1 THEN STUFF({col},2,CHARINDEX(''@'',{col})-2,REPLICATE(''x'',CASE WHEN CHARINDEX(''@'',{col})-2<0 THEN 0 ELSE CHARINDEX(''@'',{col})-2 END)) ELSE ''x@x.x'' END'),
(N'%tarjeta%',  N'partial(0,"XXXX-XXXX-XXXX-",4)', N'REPLICATE(''x'',NULLIF(LEN({col}),0)-4)+RIGHT({col},4)'),
(N'%cuenta%',   N'partial(0,"********",4)',        N'REPLICATE(''x'',NULLIF(LEN({col}),0)-4)+RIGHT({col},4)'),
(N'%dpi%',      N'default()',                      N'CASE WHEN {col} IS NULL THEN NULL ELSE REPLICATE(''x'',LEN({col})) END'),
(N'%nit%',      N'default()',                      N'CASE WHEN {col} IS NULL THEN NULL ELSE REPLICATE(''x'',LEN({col})) END'),
(N'%telefono%', N'default()',                      N'CASE WHEN {col} IS NULL THEN NULL ELSE REPLICATE(''x'',LEN({col})) END'),

-- ====== PATRONES PERSONALIZADOS (TUS NUEVOS) ======
(N'%tarjeta%',   N'partial(0,"XXXXXXXXXXXXXXX",4)', N'LEFT({col},0)+REPLICATE(''X'',15)+RIGHT({col},4)'),
(N'%cuenta%',    N'partial(0,"XXXXXXXXXXXX",4)',   N'LEFT({col},0)+REPLICATE(''X'',12)+RIGHT({col},4)'),
(N'%codigo%',    N'partial(6,"XXXXXX",4)',         N'LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
(N'%autenticacion%', N'partial(6,"XXXXXX",4)',     N'LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
(N'%magnetica%', N'partial(6,"XXXXXX",4)',         N'LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
(N'%cv2%',       N'partial(6,"XXXXXX",4)',         N'LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
(N'%cvv2%',      N'partial(6,"XXXXXX",4)',         N'LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
(N'%bin%',       N'partial(6,"XXXXXX",4)',         N'LEFT({col},6)+REPLICATE(''X'',6)+RIGHT({col},4)'),
(N'%fecha_v%',   N'default()',                     N'CONVERT(CHAR(10),GETDATE(),120)'),
(N'%nom_%',      N'partial(10,"XXXXXXXXXXXXXXXXXXXX",0)', N'LEFT({col},10)+REPLICATE(''X'',20)'),
(N'%nacimiento%',N'default()',                     N'NULL'),
(N'%bloqueo%',   N'default()',                     N'NULL'),
(N'%token%',     N'default()',                     N'NULL'),
(N'%direccion%', N'default()',                     N'''DIRECCION ENMASCARADA'''),
(N'%dir_%',      N'default()',                     N'''DIRECCION ENMASCARADA'''),
(N'%tel%',       N'default()',                     N'''0000-0000''');

-- Seguridad base
BEGIN TRY
  DENY VIEW DEFINITION ON SCHEMA::dbo TO PUBLIC;
  INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'SECURITY','dbo',NULL,NULL,'DENY VIEW DEFINITION','PUBLIC');
END TRY BEGIN CATCH INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'ERROR','dbo',NULL,NULL,'DENY VIEW DEFINITION',ERROR_MESSAGE()); END CATCH;

BEGIN TRY
  DENY SELECT ON SCHEMA::dbo TO PUBLIC;
  INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'SECURITY','dbo',NULL,NULL,'DENY SELECT','PUBLIC');
END TRY BEGIN CATCH INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'ERROR','dbo',NULL,NULL,'DENY SELECT',ERROR_MESSAGE()); END CATCH;

BEGIN TRY
  GRANT SELECT ON SCHEMA::masked TO [rol_app_lectura];
  GRANT SELECT ON SCHEMA::app    TO [rol_app_lectura];
  INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'SECURITY','masked',NULL,NULL,'GRANT SELECT','rol_app_lectura');
  INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'SECURITY','app',NULL,NULL,'GRANT SELECT','rol_app_lectura');
END TRY BEGIN CATCH 
  INSERT INTO dbo.Masked_Audit VALUES (DEFAULT,'ERROR','masked/app',NULL,NULL,'GRANT SELECT',ERROR_MESSAGE()); 
END CATCH;
GO