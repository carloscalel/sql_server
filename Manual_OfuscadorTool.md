# Manual completo de OfuscadorTool

**Proyecto:** OfuscadorTool  
**Tipo:** Herramienta Windows Forms para SQL Server  
**Propósito:** Automatizar el despliegue de un sistema de ofuscamiento/enmascaramiento de datos sensibles usando patrones, reglas manuales, vistas en esquema `masked`, Dynamic Data Masking, políticas de permisos y `DEFAULT_SCHEMA` controlado.

---

## 1. Objetivo de la herramienta

OfuscadorTool sirve para instalar y administrar un sistema de enmascaramiento de datos sobre bases SQL Server sin que tengas que ejecutar todos los scripts manualmente en SSMS.

La herramienta funciona como un asistente o wizard. Tú agregas un servidor, cargas sus bases, seleccionas dónde aplicar el proceso, eliges opciones de ofuscamiento y luego ejecutas. Internamente, la herramienta toma los scripts SQL incluidos dentro del proyecto y los ejecuta en el orden correcto.

El objetivo principal no es borrar ni modificar los datos reales, sino controlar cómo se visualizan los datos sensibles según el usuario que consulta.

Ejemplos de datos sensibles:

- DPI.
- NIT.
- Teléfono.
- Correo electrónico.
- Nombre de persona.
- Dirección.
- Fecha de nacimiento.
- Salario.
- Número de cuenta.
- Identificadores personales.
- Observaciones con información privada.

---

## 2. Qué hace en términos generales

La herramienta puede realizar estas acciones:

1. Guardar conexiones a servidores SQL Server.
2. Probar conexión al servidor.
3. Listar bases de datos disponibles.
4. Seleccionar bases de datos objetivo.
5. Instalar tablas de configuración del sistema de enmascaramiento.
6. Cargar patrones base para detectar columnas sensibles.
7. Crear procedimientos almacenados de administración.
8. Aplicar Dynamic Data Masking, también llamado DDM.
9. Crear vistas enmascaradas en el esquema `masked`.
10. Crear triggers DML seguros sobre vistas cuando aplique.
11. Configurar usuarios o roles para usar `DEFAULT_SCHEMA = masked`.
12. Copiar permisos puntuales desde tablas originales hacia vistas enmascaradas.
13. Generar auditoría de acciones, errores y simulaciones.
14. Ejecutar en modo `DryRun`, es decir, simulación.
15. Reprocesar máscaras, vistas y reglas de forma controlada.

---

## 3. Conceptos clave

### 3.1 Ofuscamiento

Ofuscar significa mostrar un valor transformado para que el dato real no quede visible completamente.

Ejemplo:

```text
Dato real: 1234567890101
Dato ofuscado: XXXXXXXXX0101
```

Otro ejemplo:

```text
Dato real: juan.perez@correo.com
Dato ofuscado: jXXX@XXXX.com
```

La finalidad es que el usuario pueda trabajar con la tabla o vista sin ver datos sensibles completos.

---

### 3.2 Dynamic Data Masking, DDM

Dynamic Data Masking es una característica de SQL Server que permite definir máscaras sobre columnas reales.

Ejemplo:

```sql
ALTER TABLE dbo.Clientes
ALTER COLUMN Correo ADD MASKED WITH (FUNCTION = 'email()');
```

La tabla conserva el dato real, pero los usuarios sin permisos para ver el dato completo observan el dato enmascarado.

Ventajas:

- No cambia físicamente los datos.
- Es nativo de SQL Server.
- Funciona aunque el usuario consulte la tabla base.
- Ayuda a reducir exposición accidental de información.

Limitaciones:

- No sustituye cifrado.
- No protege frente a usuarios con privilegios altos.
- No debe tratarse como única medida de seguridad.
- Requiere revisar permisos como `UNMASK` y privilegios administrativos.

---

### 3.3 Vistas enmascaradas

Además del DDM, la herramienta puede crear vistas en un esquema separado llamado `masked`.

Ejemplo:

```text
dbo.Clientes       -- tabla real
masked.Clientes    -- vista enmascarada
```

La vista puede mostrar columnas transformadas con expresiones SQL.

Ejemplo conceptual:

```sql
SELECT
    ClienteId,
    LEFT(Nombre, 1) + 'XXXX' AS Nombre,
    'XXXX' + RIGHT(DPI, 4) AS DPI,
    Correo
FROM dbo.Clientes;
```

El usuario puede consultar:

```sql
SELECT * FROM masked.Clientes;
```

sin tocar directamente la tabla real.

---

### 3.4 Esquema `masked`

El esquema `masked` es el espacio donde se crean las vistas enmascaradas.

Ejemplo:

```text
masked.Clientes
masked.Empleados
masked.Proveedores
```

La intención es que este esquema sea la capa de consulta segura.

---

### 3.5 DEFAULT_SCHEMA

`DEFAULT_SCHEMA` permite indicar qué esquema debe buscar primero SQL Server cuando un usuario consulta un objeto sin escribir el esquema.

Ejemplo:

```sql
ALTER USER masked_reader WITH DEFAULT_SCHEMA = masked;
```

Después, si el usuario ejecuta:

```sql
SELECT * FROM Clientes;
```

SQL Server intentará resolver primero:

```sql
SELECT * FROM masked.Clientes;
```

Esto ayuda a que los usuarios no tengan que escribir `masked.Clientes` en todas sus consultas.

Importante:

`DEFAULT_SCHEMA` no es seguridad por sí solo. Si el usuario todavía tiene permiso sobre `dbo.Clientes`, puede escribir:

```sql
SELECT * FROM dbo.Clientes;
```

Por eso el control real se hace con permisos.

---

### 3.6 DryRun

`DryRun` es el modo simulación.

Cuando está activado, la herramienta debe intentar reportar lo que haría, sin aplicar cambios definitivos.

Uso recomendado:

```text
Primera ejecución: DryRun = true
Segunda ejecución validada: DryRun = false
```

Esto reduce el riesgo de aplicar cambios sin revisión.

---

## 4. Arquitectura del proyecto

La estructura base del proyecto es:

```text
OfuscadorTool
│
├── Models
│   ├── ServerConnection.cs
│   ├── GlobalConfig.cs
│   ├── DeploymentResult.cs
│   └── PrincipalPolicy.cs
│
├── Services
│   ├── ConfigService.cs
│   ├── SqlScriptService.cs
│   ├── DeploymentService.cs
│   └── EncryptionService.cs
│
├── Forms
│   ├── WelcomeStepControl.cs
│   ├── ServerStepControl.cs
│   ├── DatabaseStepControl.cs
│   ├── OptionsStepControl.cs
│   ├── PrincipalPolicyStepControl.cs
│   ├── ReviewStepControl.cs
│   ├── ExecuteStepControl.cs
│   └── ServerDialog.cs
│
├── Scripts
│   ├── setup.sql
│   ├── sp_ManageColumnRule.sql
│   ├── sp_CreateViewWithDml.sql
│   ├── apply_ddm.sql
│   ├── 02_deploy_all.sql
│   ├── 04_policy_by_table_SAFE.sql
│   └── 06_reprocess_all_CONTROLADO.sql
│
├── Documentation
│   └── README_PROYECTO.md
│
├── MainForm.cs
└── OfuscadorTool.csproj
```

---

## 5. Dónde guarda las conexiones

La herramienta guarda las conexiones localmente en un archivo JSON dentro del perfil del usuario de Windows.

Ruta:

```text
C:\Users\TU_USUARIO\AppData\Roaming\OfuscadorTool\config.json
```

Forma rápida de abrir la carpeta:

```text
Win + R
%APPDATA%\OfuscadorTool
```

Ahí debe aparecer:

```text
config.json
```

---

### 5.1 Qué contiene el archivo config.json

El archivo puede guardar información como:

```json
{
  "Servers": [
    {
      "Id": "identificador-unico",
      "Name": "GINEBRA",
      "Host": "GINEBRA",
      "InstanceName": "",
      "UseWindowsAuth": true,
      "Username": null,
      "EncryptedPassword": null,
      "IsEnabled": true,
      "EncryptConnection": false,
      "TrustServerCertificate": true,
      "ConnectTimeout": 30
    }
  ],
  "DefaultOptions": {
    "ApplyDDM": true,
    "CreateViews": true,
    "ForceReapply": false,
    "CreateSynonyms": true,
    "CommandTimeout": 300,
    "DryRun": true,
    "MaskingMode": "HYBRID"
  }
}
```

---

### 5.2 Seguridad de contraseñas

Si usas autenticación SQL Server, la contraseña no debe guardarse como texto plano.

La herramienta usa protección local de Windows mediante DPAPI. Esto significa que la contraseña cifrada solo puede descifrarse normalmente desde el mismo usuario de Windows que la guardó.

Campo esperado:

```text
EncryptedPassword
```

No debe existir un campo con contraseña visible en texto plano.

---

### 5.3 Cómo borrar las conexiones guardadas

Si deseas empezar de cero, cierra la herramienta y borra:

```text
%APPDATA%\OfuscadorTool\config.json
```

La próxima vez que abras la herramienta, se iniciará sin servidores guardados.

---

## 6. ¿Es necesario ejecutar los scripts manualmente?

No. El uso normal de la herramienta no requiere ejecutar scripts manualmente.

Los scripts están dentro de la carpeta:

```text
Scripts
```

Y están integrados al proyecto como recursos embebidos. Cuando presionas ejecutar en el wizard, la herramienta lee esos scripts y los ejecuta contra la base seleccionada.

Solo conviene abrirlos manualmente si quieres:

- Revisar qué hará cada script.
- Auditar cambios.
- Depurar errores.
- Probar una parte específica en laboratorio.
- Ajustar patrones, reglas o permisos.

---

## 7. Orden de ejecución de scripts

El orden recomendado es:

```text
1. setup.sql
2. sp_ManageColumnRule.sql
3. sp_CreateViewWithDml.sql
4. apply_ddm.sql
5. 02_deploy_all.sql
6. 04_policy_by_table_SAFE.sql
```

Si se activa reprocesamiento:

```text
06_reprocess_all_CONTROLADO.sql
```

puede ejecutarse antes de reaplicar DDM y recrear vistas.

---

## 8. Qué hace cada script

### 8.1 setup.sql

Crea la estructura base del sistema.

Objetos esperados:

```text
dbo.Masked_Config
dbo.Masked_Patterns
dbo.Masked_ColumnRules
dbo.Masked_ManualSelection
dbo.Masked_Exceptions
dbo.Masked_Audit
dbo.Masked_PrincipalPolicy
```

También debe crear el esquema:

```text
masked
```

si no existe.

Esta es la base del sistema. Sin este script, los demás no tendrán dónde leer configuración.

---

### 8.2 dbo.Masked_Config

Tabla de configuración general.

Ejemplos de llaves:

```text
MaskingMode
MaskDryRun
MaskForceReapply
CreateMaskedViews
CreateSynonyms
ApplySafePolicy
SkipTablesWithComputed
```

Ejemplo:

```sql
SELECT * FROM dbo.Masked_Config;
```

---

### 8.3 dbo.Masked_Patterns

Guarda patrones de detección automática.

Ejemplos:

```text
%DPI%
%NIT%
%EMAIL%
%CORREO%
%TELEFONO%
%TEL%
%NOMBRE%
%DIRECCION%
%FECHA_NACIMIENTO%
%SALARIO%
```

Sirve para el modo por coincidencia y para el modo híbrido.

---

### 8.4 dbo.Masked_ColumnRules

Guarda reglas manuales por columna.

Ejemplo conceptual:

```text
SchemaName: dbo
TableName: Clientes
ColumnName: DPI
MaskFunction: partial
MaskParams: partial(0,"XXXX",4)
```

Sirve cuando necesitas controlar una columna específica.

---

### 8.5 dbo.Masked_ManualSelection

Guarda columnas seleccionadas manualmente.

Sirve para el modo manual y para complementar el modo híbrido.

---

### 8.6 dbo.Masked_Exceptions

Guarda columnas que no deben ofuscarse aunque coincidan con patrones.

Ejemplo:

```text
dbo.Productos.Nombre
```

Aunque `Nombre` sea un patrón sensible, en una tabla de productos podría no ser dato personal.

---

### 8.7 dbo.Masked_Audit

Guarda acciones, errores, advertencias y resultados.

Después de cada ejecución conviene revisar:

```sql
SELECT TOP 100 *
FROM dbo.Masked_Audit
ORDER BY AuditId DESC;
```

---

### 8.8 dbo.Masked_PrincipalPolicy

Guarda políticas para usuarios o roles.

Ejemplo:

```text
PrincipalName: masked_reader
PrincipalType: SQL_USER
ApplyDefaultSchema: true
MirrorObjectPermissions: true
CopyDmlPermissions: false
BaseAccessAction: REPORT_ONLY
IsEnabled: true
```

Esta tabla es fundamental para aplicar `DEFAULT_SCHEMA = masked` y copiar permisos hacia vistas.

---

### 8.9 sp_ManageColumnRule.sql

Crea un procedimiento almacenado para administrar reglas por columna.

Acciones esperadas:

```text
ADD
UPDATE
ENABLE
DISABLE
DELETE
```

Permite manejar reglas sin editar directamente tablas internas.

---

### 8.10 sp_CreateViewWithDml.sql

Crea el procedimiento que genera vistas enmascaradas.

Ejemplo:

```text
dbo.Clientes -> masked.Clientes
```

También puede generar triggers `INSTEAD OF` para permitir operaciones DML controladas.

Punto crítico:

Los triggers no deben permitir que una actualización desde la vista reemplace datos reales por valores enmascarados como `XXXX`.

---

### 8.11 apply_ddm.sql

Aplica Dynamic Data Masking sobre columnas candidatas.

Debe tomar en cuenta:

- Modo de ofuscamiento.
- Excepciones.
- Reglas manuales.
- Columnas ya enmascaradas.
- `ForceReapply`.
- `DryRun`.
- Compatibilidad del tipo de dato.

---

### 8.12 02_deploy_all.sql

Ejecuta la creación masiva de vistas enmascaradas.

Normalmente recorre tablas candidatas y llama al procedimiento que crea vistas.

---

### 8.13 04_policy_by_table_SAFE.sql

Aplica políticas de permisos de forma controlada.

Funciones principales:

- Leer `dbo.Masked_PrincipalPolicy`.
- Aplicar `DEFAULT_SCHEMA = masked` a usuarios configurados.
- Copiar permisos desde tablas originales hacia vistas.
- Evitar regalar permisos generales.
- Respetar permisos puntuales.
- Reportar acceso directo a tablas base.

Debe usarse primero en modo seguro o `DryRun`.

---

### 8.14 06_reprocess_all_CONTROLADO.sql

Permite reprocesar la configuración.

Modos:

```text
SOFT
FORCE_DDM
FULL_REBUILD
```

---

## 9. Modos de ofuscamiento

La herramienta contempla tres formas de trabajar:

```text
PATTERN
MANUAL
HYBRID
```

---

### 9.1 PATTERN: por coincidencia

Detecta columnas automáticamente por nombre.

Ejemplo:

```text
DPI
NIT
Correo
Email
Telefono
Nombre
Direccion
FechaNacimiento
```

Si una columna coincide con un patrón en `dbo.Masked_Patterns`, se considera candidata.

Ventajas:

- Rápido.
- Útil para primera revisión.
- Bueno para bases grandes.

Riesgos:

- Puede detectar falsos positivos.
- Puede omitir columnas con nombres no evidentes.

Ejemplo de falso positivo:

```text
dbo.Productos.Nombre
```

Aquí `Nombre` puede ser nombre de producto, no nombre de persona.

---

### 9.2 MANUAL: por columnas seleccionadas

Solo ofusca columnas configuradas manualmente en:

```text
dbo.Masked_ColumnRules
dbo.Masked_ManualSelection
```

Ventajas:

- Máximo control.
- Menos falsos positivos.
- Recomendado cuando ya existe inventario de columnas sensibles.

Desventajas:

- Requiere más trabajo.
- Puedes olvidar columnas sensibles si el análisis no está completo.

---

### 9.3 HYBRID: híbrido

Combina:

```text
Patrones automáticos
Reglas manuales
Selección manual
Excepciones
```

Es el modo recomendado para uso real.

Flujo recomendado:

```text
1. Ejecutar en PATTERN con DryRun.
2. Revisar columnas detectadas.
3. Agregar excepciones para falsos positivos.
4. Agregar reglas manuales para columnas faltantes.
5. Cambiar a HYBRID.
6. Ejecutar otra vez en DryRun.
7. Ejecutar sin DryRun cuando esté validado.
```

---

## 10. Prioridad de reglas

La prioridad correcta debe ser:

```text
1. Excepciones
2. Reglas manuales por columna
3. Selección manual
4. Coincidencias por patrón
```

Esto significa:

- Si una columna está en excepciones, no se ofusca.
- Si tiene regla manual, se usa esa regla.
- Si está seleccionada manualmente, se incluye.
- Si no tiene nada anterior, se evalúan patrones.

---

## 11. Uso del wizard

### 11.1 Paso 1: Bienvenida

Explica el objetivo y advertencias generales.

Recomendación:

Leer antes de avanzar y confirmar que se trabajará primero sobre una base de prueba.

---

### 11.2 Paso 2: Servidores

Permite agregar, editar, quitar y probar conexiones.

Campos importantes:

```text
Nombre
Host
Instancia
Windows Authentication
Usuario
Contraseña
Encrypt
Trust Server Certificate
Timeout
```

---

### 11.3 Cómo configurar Host e Instancia

Si en SSMS conectas con:

```text
GINEBRA
```

entonces en la herramienta:

```text
Host: GINEBRA
Instancia: vacío
```

Si en SSMS conectas con:

```text
GINEBRA\SQLEXPRESS
```

entonces:

```text
Host: GINEBRA
Instancia: SQLEXPRESS
```

Si es local:

```text
Host: localhost
Instancia: vacío
```

O:

```text
Host: .
Instancia: vacío
```

Incorrecto común:

```text
Host: GINEBRA
Instancia: GINEBRA
```

Eso intenta conectar a:

```text
GINEBRA\GINEBRA
```

que normalmente no existe.

---

### 11.4 Paso 3: Bases de datos

Carga bases desde el servidor.

Debe excluir normalmente:

```text
master
model
msdb
tempdb
```

Modos de selección:

```text
Todas
Todas excepto
Solo estas
```

Para pruebas, usar solo una base de laboratorio.

---

### 11.5 Paso 4: Opciones

Opciones principales:

```text
ApplyDDM
CreateViews
CreateSynonyms
ForceReapply
DryRun
ApplySafePolicy
MaskingMode
RunReprocess
ReprocessMode
CommandTimeout
```

Primera prueba recomendada:

```text
ApplyDDM = true
CreateViews = true
CreateSynonyms = true
ForceReapply = false
DryRun = true
ApplySafePolicy = false
MaskingMode = HYBRID
RunReprocess = false
```

---

### 11.6 Paso 5: Usuarios / políticas

Aquí defines usuarios o roles que trabajarán con la capa enmascarada.

Ejemplo:

```text
PrincipalName: masked_reader
PrincipalType: SQL_USER
IsEnabled: true
ApplyDefaultSchema: true
MirrorObjectPermissions: true
CopyDmlPermissions: false
BaseAccessAction: REPORT_ONLY
```

No aplicar a:

```text
sysadmin
db_owner
cuentas ETL
cuentas de mantenimiento
usuarios administrativos
cuentas de aplicación críticas
```

---

### 11.7 Paso 6: Revisión

Antes de ejecutar, revisar:

- Servidor.
- Bases seleccionadas.
- Modo de ofuscamiento.
- Estado de DryRun.
- Si se aplicará DDM.
- Si se crearán vistas.
- Si se aplicarán políticas.
- Usuarios afectados.
- Acción sobre tabla base.

---

### 11.8 Paso 7: Ejecución

Muestra progreso, log y resultados.

Después de ejecutar, revisar:

```sql
SELECT TOP 100 * FROM dbo.Masked_Audit ORDER BY AuditId DESC;
```

---

## 12. Prueba completa en laboratorio

### 12.1 Crear base de prueba

```sql
CREATE DATABASE OfuscadorTest;
GO

USE OfuscadorTest;
GO

CREATE TABLE dbo.Clientes
(
    ClienteId INT IDENTITY(1,1) PRIMARY KEY,
    Nombre NVARCHAR(100),
    DPI NVARCHAR(20),
    NIT NVARCHAR(20),
    Correo NVARCHAR(100),
    Email NVARCHAR(100),
    Telefono NVARCHAR(20),
    FechaNacimiento DATE,
    Salario DECIMAL(12,2),
    Observaciones NVARCHAR(300)
);
GO

INSERT INTO dbo.Clientes
(
    Nombre, DPI, NIT, Correo, Email, Telefono, FechaNacimiento, Salario, Observaciones
)
VALUES
(
    N'Juan Pérez',
    N'1234567890101',
    N'1234567-8',
    N'juan.perez@correo.com',
    N'juan.perez@correo.com',
    N'55551234',
    '1995-05-10',
    4500.50,
    N'Cliente con datos sensibles'
),
(
    N'María López',
    N'9876543210101',
    N'7654321-9',
    N'maria.lopez@correo.com',
    N'maria.lopez@correo.com',
    N'55559876',
    '1990-02-15',
    6200.00,
    N'Otra observación sensible'
);
GO
```

---

### 12.2 Crear usuario de prueba

```sql
USE master;
GO

CREATE LOGIN masked_reader
WITH PASSWORD = 'Test_123456789!';
GO

USE OfuscadorTest;
GO

CREATE USER masked_reader FOR LOGIN masked_reader;
GO

GRANT SELECT ON dbo.Clientes TO masked_reader;
GO
```

---

### 12.3 Primera ejecución desde la herramienta

Configuración:

```text
Base: OfuscadorTest
DryRun: true
ApplyDDM: true
CreateViews: true
ApplySafePolicy: false
MaskingMode: HYBRID
```

Ejecutar y revisar log.

---

### 12.4 Segunda ejecución real

Si no hubo errores:

```text
DryRun: false
ApplyDDM: true
CreateViews: true
ApplySafePolicy: false
```

Ejecutar.

---

### 12.5 Validar estructura

```sql
USE OfuscadorTest;
GO

SELECT * FROM dbo.Masked_Config;
SELECT TOP 100 * FROM dbo.Masked_Audit ORDER BY AuditId DESC;
SELECT * FROM dbo.Masked_Patterns;
```

Validar esquema:

```sql
SELECT name
FROM sys.schemas
WHERE name = 'masked';
```

Validar vistas:

```sql
SELECT
    s.name AS SchemaName,
    v.name AS ViewName
FROM sys.views v
INNER JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'masked';
```

Validar DDM:

```sql
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    c.name AS ColumnName,
    mc.masking_function
FROM sys.masked_columns mc
INNER JOIN sys.columns c
    ON mc.object_id = c.object_id
   AND mc.column_id = c.column_id
INNER JOIN sys.tables t
    ON c.object_id = t.object_id
ORDER BY t.name, c.column_id;
```

---

### 12.6 Probar vistas

```sql
SELECT * FROM masked.Clientes;
```

---

### 12.7 Probar como usuario limitado

```sql
USE OfuscadorTest;
GO

EXECUTE AS USER = 'masked_reader';

SELECT * FROM dbo.Clientes;
SELECT * FROM masked.Clientes;

REVERT;
GO
```

---

### 12.8 Probar DEFAULT_SCHEMA

En la herramienta, agregar política:

```text
PrincipalName: masked_reader
PrincipalType: SQL_USER
ApplyDefaultSchema: true
MirrorObjectPermissions: true
CopyDmlPermissions: false
BaseAccessAction: REPORT_ONLY
IsEnabled: true
```

Activar:

```text
ApplySafePolicy = true
DryRun = true
BaseAccessAction = REPORT_ONLY
```

Ejecutar.

Si todo está bien, repetir con:

```text
DryRun = false
```

Probar:

```sql
USE OfuscadorTest;
GO

EXECUTE AS USER = 'masked_reader';

SELECT * FROM Clientes;

REVERT;
GO
```

Si funciona, `Clientes` debe resolver hacia `masked.Clientes`.

---

## 13. Validaciones importantes

### 13.1 Ver configuración

```sql
SELECT * FROM dbo.Masked_Config;
```

### 13.2 Ver auditoría

```sql
SELECT TOP 200 *
FROM dbo.Masked_Audit
ORDER BY AuditId DESC;
```

### 13.3 Ver vistas creadas

```sql
SELECT s.name, v.name
FROM sys.views v
JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'masked';
```

### 13.4 Ver columnas con máscara DDM

```sql
SELECT
    OBJECT_SCHEMA_NAME(object_id) AS SchemaName,
    OBJECT_NAME(object_id) AS TableName,
    name AS ColumnName,
    masking_function
FROM sys.masked_columns;
```

### 13.5 Ver DEFAULT_SCHEMA de usuario

```sql
SELECT name, default_schema_name
FROM sys.database_principals
WHERE name = 'masked_reader';
```

### 13.6 Ver permisos de un usuario

```sql
SELECT
    USER_NAME(dp.grantee_principal_id) AS PrincipalName,
    OBJECT_SCHEMA_NAME(dp.major_id) AS ObjectSchema,
    OBJECT_NAME(dp.major_id) AS ObjectName,
    dp.permission_name,
    dp.state_desc
FROM sys.database_permissions dp
WHERE dp.class = 1
  AND USER_NAME(dp.grantee_principal_id) = 'masked_reader'
ORDER BY ObjectSchema, ObjectName, permission_name;
```

---

## 14. Reprocesamiento

### 14.1 SOFT

Reprocesamiento suave.

Uso:

- Actualizar configuración.
- Recrear vistas.
- Releer patrones.
- No forzar DDM existente.

Recomendado para uso normal.

---

### 14.2 FORCE_DDM

Reaplica máscaras DDM.

Uso:

- Cambiaste reglas.
- Cambiaste patrones.
- Quieres corregir columnas ya enmascaradas.
- Quieres reaplicar funciones de máscara.

Primero usar con DryRun.

---

### 14.3 FULL_REBUILD

Reconstrucción completa.

Uso recomendado:

- Laboratorio.
- QA.
- Ambientes temporales.

No recomendable directamente en producción sin plan de rollback.

---

## 15. Políticas de permisos

### 15.1 Principio de seguridad

No regalar permisos generales.

Si un usuario tenía permiso solo sobre:

```text
dbo.Clientes
```

lo correcto es darle permiso equivalente solo sobre:

```text
masked.Clientes
```

No sobre todo:

```text
masked.*
```

---

### 15.2 REPORT_ONLY

Modo más seguro.

No quita acceso original, solo reporta.

Uso recomendado:

```text
BaseAccessAction = REPORT_ONLY
```

---

### 15.3 REVOKE_EXPLICIT_OBJECT_PERMISSIONS

Quita permisos explícitos sobre tabla base.

Solo usar después de confirmar que:

- La vista existe.
- El usuario puede consultar la vista.
- Las consultas funcionan.
- No se rompe ningún proceso.

---

### 15.4 DENY_BASE_FOR_POLICY_PRINCIPALS

Aplica denegación explícita sobre tabla base.

Debe usarse con máximo cuidado.

No activar en primera etapa.

---

## 16. Problemas comunes y soluciones

### 16.1 Error 26 al conectar

Mensaje típico:

```text
Error relacionado con la red o específico de la instancia...
Error 26 - Error al buscar el servidor/instancia especificado.
```

Causas:

- Host mal escrito.
- Instancia incorrecta.
- SQL Server Browser apagado.
- Puerto bloqueado.
- SQL Server no permite conexiones remotas.
- Se puso el mismo nombre en host e instancia sin que exista esa instancia.

Solución:

Si en SSMS usas:

```text
GINEBRA
```

en la herramienta debe ser:

```text
Host: GINEBRA
Instancia: vacío
```

Si en SSMS usas:

```text
GINEBRA\SQLEXPRESS
```

entonces:

```text
Host: GINEBRA
Instancia: SQLEXPRESS
```

---

### 16.2 Error de login

Si el servidor sí responde, pero falla usuario/contraseña, revisar:

- Usuario SQL existe.
- Contraseña correcta.
- Login habilitado.
- SQL Server permite autenticación mixta.
- Usuario tiene acceso a la base.

---

### 16.3 Error por certificado

Para laboratorio se puede probar con:

```text
Encrypt = false
TrustServerCertificate = true
```

o:

```text
Encrypt = true
TrustServerCertificate = true
```

Para producción, lo correcto es usar certificado válido.

---

### 16.4 No aparecen bases

Revisar:

- El usuario tiene permisos para ver bases.
- Las bases están ONLINE.
- La conexión a `master` funciona.
- No estás filtrando solo bases de usuario.

---

### 16.5 No se crean vistas

Revisar:

```sql
SELECT TOP 100 * FROM dbo.Masked_Audit ORDER BY AuditId DESC;
```

Posibles causas:

- No hay columnas detectadas.
- Todo está en excepciones.
- Modo MANUAL sin columnas manuales.
- Error en procedimiento de creación.
- Permisos insuficientes.

---

### 16.6 SELECT sin esquema sigue entrando a dbo

Revisar:

- Usuario tiene `DEFAULT_SCHEMA = masked`.
- Existe `masked.Tabla`.
- Tiene permiso sobre `masked.Tabla`.
- No estás probando como sysadmin o db_owner.
- La consulta no usa explícitamente `dbo.Tabla`.

---

## 17. Buenas prácticas

1. Nunca probar primero en producción.
2. Usar base de laboratorio.
3. Usar DryRun en primera ejecución.
4. Revisar `dbo.Masked_Audit`.
5. Validar columnas detectadas.
6. Agregar excepciones para falsos positivos.
7. Agregar reglas manuales para columnas no detectadas.
8. Usar HYBRID para escenario real.
9. No activar DENY al inicio.
10. Aplicar DEFAULT_SCHEMA solo a usuarios controlados.
11. Copiar permisos puntuales, no permisos generales.
12. Mantener plan de rollback.
13. Documentar cada ejecución.

---

## 18. Checklist antes de producción

```text
[ ] Se probó en laboratorio.
[ ] Se probó en copia restaurada.
[ ] DryRun fue revisado.
[ ] Se revisó dbo.Masked_Audit.
[ ] Se validaron columnas detectadas.
[ ] Se agregaron excepciones.
[ ] Se agregaron reglas manuales.
[ ] Se validó modo HYBRID.
[ ] Se validaron vistas masked.
[ ] Se validó DDM.
[ ] Se validó DEFAULT_SCHEMA con usuario de prueba.
[ ] Se revisaron permisos copiados.
[ ] No se activó DENY sin aprobación.
[ ] Existe plan de rollback.
[ ] Se documentó el cambio.
```

---

## 19. Plan de implementación recomendado

### Fase 1: Descubrimiento

```text
MaskingMode = PATTERN
DryRun = true
ApplySafePolicy = false
```

Objetivo:

- Detectar columnas candidatas.
- Ver falsos positivos.
- Identificar faltantes.

---

### Fase 2: Ajuste

Acciones:

- Agregar excepciones.
- Agregar reglas manuales.
- Agregar columnas seleccionadas.

Configuración:

```text
MaskingMode = HYBRID
DryRun = true
```

---

### Fase 3: Despliegue técnico

```text
DryRun = false
ApplyDDM = true
CreateViews = true
ApplySafePolicy = false
```

Objetivo:

- Crear estructura.
- Aplicar DDM.
- Crear vistas.

---

### Fase 4: Política de usuarios

```text
ApplySafePolicy = true
BaseAccessAction = REPORT_ONLY
DryRun = true
```

Después:

```text
DryRun = false
```

Objetivo:

- Aplicar DEFAULT_SCHEMA.
- Copiar permisos hacia vistas.
- Reportar acceso directo a tabla base.

---

### Fase 5: Endurecimiento

Solo después de validar:

```text
REVOKE_EXPLICIT_OBJECT_PERMISSIONS
```

O con mayor cuidado:

```text
DENY_BASE_FOR_POLICY_PRINCIPALS
```

---

## 20. Plan de rollback conceptual

### 20.1 Restaurar DEFAULT_SCHEMA

```sql
ALTER USER [masked_reader] WITH DEFAULT_SCHEMA = dbo;
```

### 20.2 Quitar permisos sobre vistas

```sql
REVOKE SELECT ON OBJECT::masked.Clientes FROM masked_reader;
```

### 20.3 Eliminar vistas

```sql
DROP VIEW masked.Clientes;
```

### 20.4 Quitar DDM

```sql
ALTER TABLE dbo.Clientes
ALTER COLUMN Correo DROP MASKED;
```

### 20.5 Mantener auditoría

Normalmente conviene mantener:

```text
dbo.Masked_Audit
dbo.Masked_Config
dbo.Masked_Patterns
```

hasta terminar la revisión.

---

## 21. Recomendaciones de mejora futura

La herramienta podría evolucionar con:

- Pantalla visual para patrones.
- Pantalla visual para excepciones.
- Árbol servidor/base/tabla/columna para selección manual.
- Reporte exportable a Excel.
- Generador de script DryRun.
- Modo rollback automático.
- Comparador antes/después.
- Inventario de datos sensibles.
- Prueba de consulta como usuario.
- Panel de permisos efectivos.
- Registro de versión de despliegue.
- Importación/exportación de configuración.
- Integración con control de cambios.
- Validación de impacto antes de DENY.

---

## 22. Guía rápida de uso

```text
1. Abrir OfuscadorTool.
2. Agregar servidor SQL Server.
3. Probar conexión.
4. Cargar bases.
5. Seleccionar base de laboratorio.
6. Elegir MaskingMode = HYBRID.
7. Activar ApplyDDM y CreateViews.
8. Mantener DryRun = true.
9. Ejecutar.
10. Revisar log y dbo.Masked_Audit.
11. Ejecutar con DryRun = false si todo está correcto.
12. Validar vistas masked.
13. Agregar usuario de prueba en políticas.
14. Aplicar política con REPORT_ONLY.
15. Probar SELECT * FROM Tabla como usuario.
16. Ajustar excepciones y reglas.
17. Repetir hasta estabilizar.
```

---

## 23. Resumen final

OfuscadorTool convierte un conjunto de scripts SQL de enmascaramiento en una herramienta guiada, más controlada y repetible.

Su valor principal está en:

```text
Automatizar detección
Permitir modo DryRun
Aplicar DDM
Crear vistas masked
Administrar DEFAULT_SCHEMA
Copiar permisos sin regalarlos
Respetar permisos puntuales
Auditar acciones
Permitir reprocesamiento
Reducir errores manuales
```

La recomendación es usarlo progresivamente:

```text
Laboratorio -> DryRun -> Ajustes -> Despliegue técnico -> Política REPORT_ONLY -> Validación -> Endurecimiento
```

No debe verse como un botón mágico de producción, sino como una herramienta de apoyo para aplicar ofuscamiento con control, revisión y trazabilidad.
