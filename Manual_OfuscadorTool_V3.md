# Manual completo de OfuscadorTool – Wizard de Enmascaramiento SQL Server

**Proyecto:** OfuscadorTool  
**Versión del manual:** V3 – Usuarios, roles, exclusiones y política `DEFAULT_SCHEMA = masked`  
**Tipo de herramienta:** Aplicación Windows Forms en C# para SQL Server  
**Objetivo:** Automatizar la detección, configuración, aplicación y administración de enmascaramiento/ofuscamiento de datos sensibles en bases SQL Server.  
**Uso recomendado:** Laboratorio, QA, copias restauradas y, después de validación, ambientes productivos controlados.

---

## 1. Resumen general

OfuscadorTool es una herramienta tipo **wizard** que permite aplicar un sistema de enmascaramiento/ofuscamiento sobre bases SQL Server sin ejecutar manualmente todos los scripts desde SSMS.

El flujo principal es:

```text
1. Registrar uno o varios servidores SQL Server.
2. Probar conexión.
3. Cargar bases de datos.
4. Seleccionar bases objetivo.
5. Definir opciones de enmascaramiento.
6. Seleccionar modo de ofuscamiento:
   - Por coincidencia/patrones.
   - Por columnas manuales.
   - Híbrido.
7. Configurar usuarios, roles y exclusiones.
8. Revisar configuración.
9. Ejecutar en modo DryRun.
10. Ejecutar realmente después de validar.
```

La herramienta está diseñada para trabajar con una capa segura basada en:

```text
Tablas reales:       dbo.Tabla
Vistas enmascaradas: masked.Tabla
```

Con esto, un usuario configurado con:

```sql
DEFAULT_SCHEMA = masked
```

puede consultar:

```sql
SELECT * FROM Clientes;
```

y SQL Server intentará resolver primero:

```sql
masked.Clientes
```

Si no existe en `masked`, entonces puede resolver hacia el esquema `dbo`, siempre que los permisos lo permitan.

---

## 2. Qué problema resuelve

En muchas bases de datos existen columnas sensibles como:

```text
DPI
NIT
Nombre
Dirección
Teléfono
Correo
Fecha de nacimiento
Salario
Cuenta bancaria
Observaciones personales
Códigos internos sensibles
Información de clientes
Información de empleados
Información de beneficiarios
```

El problema es que varios usuarios pueden necesitar consultar información para soporte, auditoría, reportería o análisis, pero no necesariamente deben ver el valor real completo.

OfuscadorTool permite:

```text
Detectar columnas sensibles.
Aplicar Dynamic Data Masking.
Crear vistas enmascaradas.
Copiar permisos puntuales hacia vistas.
Aplicar DEFAULT_SCHEMA = masked a usuarios controlados.
Excluir usuarios o roles que no deben modificarse.
Simular cambios antes de aplicarlos.
Registrar auditoría.
Reprocesar configuraciones.
```

---

## 3. Conceptos clave

### 3.1 Enmascaramiento

El enmascaramiento consiste en ocultar total o parcialmente el valor real.

Ejemplo:

```text
Dato real:     1234567890101
Dato mostrado: XXXX0101
```

O:

```text
Dato real:     juan.perez@correo.com
Dato mostrado: jXXX@XXXX.com
```

---

### 3.2 Ofuscamiento

En este proyecto, ofuscamiento se usa como concepto general para mostrar información alterada, parcial, nula o protegida, sin modificar necesariamente el dato original.

Puede hacerse mediante:

```text
Dynamic Data Masking
Vistas masked
Expresiones SQL
Reglas manuales
Patrones automáticos
```

---

### 3.3 Dynamic Data Masking, DDM

DDM es una característica de SQL Server que permite definir máscaras sobre columnas reales.

Ejemplo:

```sql
ALTER TABLE dbo.Clientes
ALTER COLUMN Correo ADD MASKED WITH (FUNCTION = 'email()');
```

Ventajas:

```text
No modifica físicamente el dato.
Funciona sobre la tabla real.
Es transparente para muchas consultas.
```

Limitaciones:

```text
No reemplaza cifrado.
Usuarios privilegiados pueden ver datos reales.
No es una solución completa contra administradores.
Algunas funciones dependen del tipo de dato.
```

---

### 3.4 Vistas en esquema `masked`

La herramienta crea vistas en un esquema llamado `masked`.

Ejemplo:

```text
dbo.Clientes       -> tabla original
masked.Clientes    -> vista enmascarada
```

Cuando el usuario consulta la vista, ve información protegida.

Ejemplo:

```sql
SELECT * FROM masked.Clientes;
```

---

### 3.5 DEFAULT_SCHEMA = masked

Esta es una de las funciones principales del diseño.

Cuando un usuario tiene:

```sql
ALTER USER [usuario] WITH DEFAULT_SCHEMA = [masked];
```

y ejecuta:

```sql
SELECT * FROM Clientes;
```

SQL Server busca primero:

```text
masked.Clientes
```

Si no encuentra ese objeto, puede buscar en `dbo`, dependiendo del contexto y permisos.

Esto permite que consultas sin esquema explícito usen preferentemente la vista enmascarada.

---

### 3.6 DEFAULT_SCHEMA no es seguridad por sí solo

Es importante entender esto:

```sql
SELECT * FROM Clientes;
```

puede ir a `masked.Clientes` si `masked` es el esquema por defecto.

Pero si el usuario escribe:

```sql
SELECT * FROM dbo.Clientes;
```

podría acceder a la tabla real si todavía tiene permiso.

Por eso la herramienta separa:

```text
Comodidad: DEFAULT_SCHEMA = masked
Seguridad: permisos, vistas, DDM, reporte y bloqueo controlado
```

---

## 4. Componentes principales de la herramienta

La estructura del proyecto es:

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
└── MainForm.cs
```

---

## 5. Dónde guarda las conexiones

La herramienta guarda las conexiones localmente en un archivo JSON.

Ruta:

```text
C:\Users\TU_USUARIO\AppData\Roaming\OfuscadorTool\config.json
```

Forma rápida de abrir la carpeta:

```text
Win + R
%APPDATA%\OfuscadorTool
```

---

### 5.1 Qué guarda el archivo `config.json`

Guarda información como:

```text
Servidores configurados
Host
Instancia
Tipo de autenticación
Usuario SQL, si aplica
Contraseña cifrada
Opciones de conexión
Selección de bases
Opciones generales
Políticas de usuarios
Exclusiones
```

Ejemplo conceptual:

```json
{
  "Servers": [
    {
      "Name": "GINEBRA",
      "Host": "GINEBRA",
      "InstanceName": "",
      "UseWindowsAuth": true,
      "Username": null,
      "EncryptedPassword": null,
      "EncryptConnection": false,
      "TrustServerCertificate": true,
      "IsEnabled": true
    }
  ]
}
```

---

### 5.2 Seguridad de contraseña

Cuando se usa usuario SQL, la contraseña no debe guardarse como texto plano.

Se almacena cifrada usando protección de Windows, normalmente mediante DPAPI.

Esto significa que:

```text
El mismo usuario de Windows puede descifrarla.
Otro usuario de Windows no debería poder descifrarla fácilmente.
```

---

### 5.3 Cómo borrar configuración local

Si quieres reiniciar la herramienta desde cero, puedes eliminar:

```text
%APPDATA%\OfuscadorTool\config.json
```

Al abrir la herramienta nuevamente, no tendrá servidores ni políticas guardadas.

---

## 6. Scripts SQL incluidos

La herramienta incluye scripts dentro del proyecto. No es necesario ejecutarlos manualmente si se usa el wizard.

Los scripts están en:

```text
Scripts
```

y se compilan como recursos embebidos del proyecto.

---

### 6.1 ¿Tengo que correr los scripts manualmente?

No.

El wizard los ejecuta automáticamente en la base seleccionada.

Solo conviene abrirlos manualmente si deseas:

```text
Revisar el código.
Auditar qué hará.
Depurar errores.
Ejecutar pruebas aisladas.
Personalizar reglas.
```

---

### 6.2 Orden de ejecución

El orden general es:

```text
1. setup.sql
2. sp_ManageColumnRule.sql
3. sp_CreateViewWithDml.sql
4. apply_ddm.sql
5. 02_deploy_all.sql
6. 04_policy_by_table_SAFE.sql
```

Si se activa reproceso:

```text
06_reprocess_all_CONTROLADO.sql
```

puede ejecutarse antes de volver a aplicar DDM o recrear vistas.

---

## 7. Qué hace cada script

### 7.1 setup.sql

Crea la estructura base.

Objetos principales:

```text
dbo.Masked_Config
dbo.Masked_Patterns
dbo.Masked_ColumnRules
dbo.Masked_ManualSelection
dbo.Masked_Exceptions
dbo.Masked_Audit
dbo.Masked_PrincipalPolicy
dbo.Masked_PrincipalExclusions
```

También crea el esquema:

```text
masked
```

si no existe.

---

### 7.2 dbo.Masked_Config

Guarda configuración general del sistema.

Ejemplos de configuración:

```text
MaskingMode
MaskDryRun
MaskForceReapply
CreateMaskedViews
CreateSynonyms
ApplySafePolicy
SkipTablesWithComputed
BaseAccessAction
PermissionCopyScope
```

---

### 7.3 dbo.Masked_Patterns

Contiene patrones para detección automática.

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
%SALARIO%
%FECHA_NACIMIENTO%
```

Cada patrón puede tener asociada una función de máscara.

---

### 7.4 dbo.Masked_ColumnRules

Contiene reglas puntuales por columna.

Ejemplo:

```text
SchemaName: dbo
TableName: Clientes
ColumnName: DPI
MaskFunction: partial
MaskExpression: partial(0,"XXXX",4)
```

---

### 7.5 dbo.Masked_ManualSelection

Permite indicar columnas seleccionadas manualmente para ofuscar.

Esto es útil en modo manual o híbrido.

---

### 7.6 dbo.Masked_Exceptions

Permite excluir columnas que no deben ofuscarse aunque coincidan con patrones.

Ejemplo:

```text
dbo.Productos.Nombre
```

Aunque `Nombre` coincida con un patrón, puede no representar dato personal si pertenece a productos.

---

### 7.7 dbo.Masked_Audit

Guarda registro de acciones, errores y eventos.

Debe revisarse después de cada ejecución.

Consulta recomendada:

```sql
SELECT TOP 100 *
FROM dbo.Masked_Audit
ORDER BY AuditId DESC;
```

---

### 7.8 dbo.Masked_PrincipalPolicy

Guarda la política de usuarios y roles que sí se pueden modificar o configurar.

Campos conceptuales:

```text
PrincipalName
IsEnabled
ApplyDefaultSchema
MirrorObjectPermissions
CopyDmlPermissions
AddToReadRole
AddToDmlRole
BlockBaseAccess
Notes
```

---

### 7.9 dbo.Masked_PrincipalExclusions

Nueva tabla de V3.

Sirve para proteger usuarios o roles que no deben modificarse.

Si un usuario o rol está aquí con `IsEnabled = 1`, la política no debe tocarlo aunque tenga permisos.

Uso recomendado:

```text
Agregar cuentas técnicas.
Agregar cuentas ETL.
Agregar cuentas de aplicaciones críticas.
Agregar usuarios que se ingresaron pero no se deben modificar.
Agregar excepciones manuales.
```

---

## 8. Modos de ofuscamiento

La herramienta contempla tres modos:

```text
PATTERN
MANUAL
HYBRID
```

En la interfaz puede aparecer como:

```text
Por coincidencia
Por columnas
Híbrido
```

o valores similares como:

```text
patterns
manual
both
```

---

### 8.1 Modo por coincidencia o patrones

Detecta columnas por nombre.

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

Ventajas:

```text
Rápido.
Automático.
Útil para descubrimiento inicial.
Bueno para bases grandes.
```

Riesgos:

```text
Puede detectar falsos positivos.
Puede omitir columnas con nombres poco claros.
Requiere revisión con DryRun.
```

---

### 8.2 Modo por columnas manuales

Solo ofusca columnas que tú configures explícitamente.

Ventajas:

```text
Control total.
Menos falsos positivos.
Más seguro para producción madura.
```

Desventajas:

```text
Requiere inventario manual.
Puede dejar fuera columnas sensibles si no se seleccionan.
```

---

### 8.3 Modo híbrido

Combina:

```text
Patrones automáticos
+
Columnas manuales
+
Reglas puntuales
+
Excepciones
```

Es el modo recomendado después de validar.

Flujo ideal:

```text
1. Ejecutar PATTERN con DryRun.
2. Revisar columnas detectadas.
3. Agregar excepciones.
4. Agregar columnas manuales faltantes.
5. Cambiar a HYBRID.
6. Ejecutar DryRun.
7. Ejecutar real.
```

---

## 9. Prioridad de reglas

La prioridad recomendada es:

```text
1. Exclusiones
2. Reglas manuales
3. Selección manual
4. Patrones automáticos
```

Esto significa:

```text
Si algo está excluido, no se toca.
Si existe regla manual, manda la regla manual.
Si está seleccionado manualmente, se incluye.
Si no tiene nada manual, se evalúan patrones.
```

---

## 10. Pantalla de opciones

Opciones principales:

```text
Aplicar Dynamic Data Masking
Crear vistas masked
Crear sinónimos app hacia masked
Forzar reaplicación de DDM
DryRun / solo simular
Omitir tablas con columnas calculadas
Modo de selección
Aplicar política segura de permisos
Aplicar DEFAULT_SCHEMA = masked desde política
Copiar permisos puntuales a vistas
Copiar permisos INSERT/UPDATE/DELETE
Alcance copia permisos
Acción sobre tabla base
Ejecutar reproceso controlado
Modo reproceso
Timeout comandos
```

---

### 10.1 Aplicar Dynamic Data Masking

Aplica máscaras nativas de SQL Server sobre columnas reales.

---

### 10.2 Crear vistas masked

Crea vistas en el esquema `masked`.

Ejemplo:

```text
dbo.Clientes -> masked.Clientes
```

---

### 10.3 Crear sinónimos app hacia masked

Puede crear sinónimos para facilitar compatibilidad si el diseño lo requiere.

Debe probarse bien, porque puede afectar resolución de objetos.

---

### 10.4 Forzar reaplicación de DDM

Si una columna ya tenía máscara, permite quitarla y volver a aplicarla.

Usar con cuidado.

---

### 10.5 DryRun / solo simular

Primera ejecución siempre recomendada con:

```text
DryRun = true
```

---

### 10.6 Omitir tablas con columnas calculadas

Puede evitar errores al crear vistas o triggers sobre tablas con columnas calculadas.

---

### 10.7 Aplicar política segura de permisos

Activa el script de permisos y políticas.

Si está desactivado, la herramienta puede crear máscaras y vistas, pero no modifica usuarios ni permisos.

---

### 10.8 Aplicar DEFAULT_SCHEMA = masked desde política

Aplica:

```sql
ALTER USER [usuario] WITH DEFAULT_SCHEMA = masked;
```

solo a usuarios o roles definidos en política y no excluidos.

---

### 10.9 Copiar permisos puntuales a vistas

Si un usuario tiene:

```sql
GRANT SELECT ON dbo.Clientes TO usuario1;
```

la herramienta puede generar:

```sql
GRANT SELECT ON masked.Clientes TO usuario1;
```

---

### 10.10 Copiar permisos INSERT/UPDATE/DELETE

Copia permisos DML hacia vistas.

Recomendación inicial:

```text
Desactivado
```

hasta validar triggers y comportamiento.

---

### 10.11 Alcance copia permisos

Ejemplo:

```text
ALL_EXISTING_GRANTEES
POLICY_ONLY
```

#### ALL_EXISTING_GRANTEES

Copia permisos de todos los usuarios/roles existentes que ya tengan permisos sobre tablas.

No necesariamente aplica `DEFAULT_SCHEMA`.

#### POLICY_ONLY

Solo copia permisos para usuarios/roles incluidos en la política.

---

### 10.12 Acción sobre tabla base

Opciones conceptuales:

```text
REPORT_ONLY
REVOKE_EXPLICIT_OBJECT_PERMISSIONS
DENY_BASE_FOR_POLICY_PRINCIPALS
```

#### REPORT_ONLY

No quita ni bloquea permisos originales.

Es el modo recomendado al inicio.

#### REVOKE_EXPLICIT_OBJECT_PERMISSIONS

Quita permisos explícitos sobre tablas base.

Usar solo después de validar.

#### DENY_BASE_FOR_POLICY_PRINCIPALS

Bloquea acceso directo a tablas base.

Es fuerte y debe usarse con mucha precaución.

---

### 10.13 Timeout comandos

Tiempo máximo que la herramienta espera por cada comando SQL.

Ejemplo:

```text
300 = 5 minutos
900 = 15 minutos
1800 = 30 minutos
```

Recomendación:

```text
Pruebas pequeñas: 300
Base mediana: 600 a 900
Base grande: 1800
```

---

## 11. Pantalla Usuarios / políticas en V3

Esta pantalla permite administrar usuarios o roles que recibirán política de acceso.

Columnas visibles:

```text
PrincipalName
Activo
DefaultSchema
Copiar permisos
Incluir DML
Rol lectura
Rol DML
Bloquear dbo
Excluir
Notas
```

---

### 11.1 PrincipalName

Nombre del usuario o rol.

Ejemplos:

```text
masked_reader
usuario_reportes
rol_consulta
DOMINIO\GrupoReportes
```

---

### 11.2 Activo

Indica si esa política se aplicará.

Si está desactivado, se conserva en la lista pero no se procesa.

---

### 11.3 DefaultSchema

Si está marcado, la herramienta intentará aplicar:

```sql
ALTER USER [PrincipalName] WITH DEFAULT_SCHEMA = masked;
```

No se debe marcar para:

```text
db_owner
sysadmin
usuarios ETL
cuentas de aplicación críticas
usuarios técnicos
```

---

### 11.4 Copiar permisos

Indica si se copiarán permisos equivalentes desde objetos `dbo` hacia vistas `masked`.

---

### 11.5 Incluir DML

Incluye permisos:

```text
INSERT
UPDATE
DELETE
```

Usar solo si la vista y triggers están validados.

---

### 11.6 Rol lectura

Puede agregar el usuario a un rol de lectura definido por la herramienta.

Debe usarse solo si ese rol está claramente definido.

---

### 11.7 Rol DML

Puede agregar el usuario a un rol para operaciones DML.

Usar con más precaución.

---

### 11.8 Bloquear dbo

Indica intención de bloquear acceso directo a tablas base.

No activar al inicio.

Primero usar:

```text
REPORT_ONLY
```

---

### 11.9 Excluir

Nueva funcionalidad importante.

Si `Excluir` está marcado:

```text
El usuario o rol no se modifica.
No se aplica DEFAULT_SCHEMA.
No se copian permisos por política directa.
No se bloquea dbo.
Queda protegido en dbo.Masked_PrincipalExclusions.
```

Sirve para registrar explícitamente usuarios que no quieres tocar.

---

### 11.10 Notas

Campo para documentar por qué se incluye o excluye.

Ejemplos:

```text
Cuenta ETL, no modificar.
Usuario de reportería, aplicar masked.
Cuenta de aplicación crítica, excluir.
Agregado automáticamente desde permisos existentes.
```

---

## 12. Carga automática de usuarios y roles

V3 incorpora la idea de no ingresar todo uno por uno.

Botones recomendados:

```text
Agregar
Quitar
Cargar usuarios/roles
Agregar con permisos
Excluir seleccionado
```

---

### 12.1 Agregar manualmente

Permite agregar un usuario o rol específico.

Uso recomendado:

```text
Para usuarios puntuales.
Para pruebas.
Para un usuario de laboratorio.
```

---

### 12.2 Cargar usuarios/roles desde la base

Consulta `sys.database_principals` y trae usuarios/roles candidatos.

Debe excluir automáticamente:

```text
dbo
guest
INFORMATION_SCHEMA
sys
public
db_owner
db_accessadmin
db_securityadmin
db_ddladmin
db_backupoperator
db_datareader
db_datawriter
db_denydatareader
db_denydatawriter
```

También debe evitar tocar miembros de:

```text
db_owner
sysadmin
```

---

### 12.3 Agregar usuarios/roles con permisos

Este es uno de los métodos más seguros.

En lugar de traer todos los usuarios, busca quienes ya tienen permisos sobre objetos.

Ejemplo conceptual:

```sql
SELECT DISTINCT
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType
FROM sys.database_permissions perm
INNER JOIN sys.database_principals dp
    ON perm.grantee_principal_id = dp.principal_id
WHERE perm.class = 1
  AND perm.major_id > 0;
```

Uso recomendado:

```text
Agregar quienes ya tienen permisos sobre tablas.
Copiar permisos hacia vistas.
No aplicar DefaultSchema automáticamente hasta revisar.
```

---

### 12.4 Configuración recomendada al cargar masivamente

Cuando se carguen usuarios automáticamente, usar valores seguros:

```text
Activo = true
DefaultSchema = false
Copiar permisos = true
Incluir DML = false
Rol lectura = false
Rol DML = false
Bloquear dbo = false
Excluir = false
Notas = Agregado automáticamente desde permisos existentes
```

Luego tú revisas y marcas manualmente:

```text
DefaultSchema = true
```

solo para quienes deben usar `masked`.

---

## 13. Exclusiones de usuarios y roles

### 13.1 Objetivo

Evitar modificar usuarios que no deben tocarse.

Ejemplos:

```text
Cuenta de aplicación productiva.
Usuario ETL.
Usuario de integración.
Usuario administrador.
Cuenta de mantenimiento.
Cuenta de monitoreo.
Usuario que el operador decidió excluir.
```

---

### 13.2 Exclusión manual

Desde la pantalla puedes marcar:

```text
Excluir = true
```

o usar:

```text
Excluir seleccionado
```

Esto debe guardar el principal en:

```text
dbo.Masked_PrincipalExclusions
```

---

### 13.3 Exclusión automática

La herramienta debe excluir automáticamente:

```text
dbo
guest
sys
INFORMATION_SCHEMA
public
roles fijos de base
miembros de db_owner
miembros de sysadmin
```

---

### 13.4 Prioridad de exclusión

La exclusión debe tener prioridad máxima.

Orden:

```text
1. Si está excluido, no tocar.
2. Si es db_owner o sysadmin, no tocar.
3. Si está en política activa, procesar.
4. Si solo aparece por permisos existentes, copiar permisos según alcance.
```

---

## 14. Cómo debe funcionar DEFAULT_SCHEMA con exclusiones

La lógica deseada es:

```text
Usuarios incluidos:
    Pueden recibir DEFAULT_SCHEMA = masked.

Usuarios excluidos:
    No se modifica DEFAULT_SCHEMA.

db_owner/sysadmin:
    No se modifica.

Usuarios técnicos:
    Recomendado excluir.
```

Ejemplo:

```text
usuario_reportes:
    DefaultSchema = true
    Resultado: SELECT * FROM Clientes intenta masked.Clientes.

usuario_etl:
    Excluir = true
    Resultado: sigue funcionando como antes.

usuario_app:
    Excluir = true
    Resultado: no se toca.
```

---

## 15. Flujo recomendado de uso con V3

### 15.1 Primera fase: prueba técnica sin usuarios

```text
Base: laboratorio
DryRun = true
ApplyDDM = true
CreateViews = true
ApplySafePolicy = false
MaskingMode = HYBRID
```

Ejecutar y revisar auditoría.

---

### 15.2 Segunda fase: aplicar DDM y vistas sin política

```text
DryRun = false
ApplyDDM = true
CreateViews = true
ApplySafePolicy = false
```

Validar:

```sql
SELECT * FROM masked.Clientes;
```

---

### 15.3 Tercera fase: cargar usuarios con permisos

En pantalla Usuarios / políticas:

```text
Agregar con permisos
```

Revisar la lista.

Marcar como excluidos:

```text
Cuentas ETL
Cuentas de aplicación
Cuentas administrativas
Usuarios técnicos
Usuarios que no deben cambiar
```

---

### 15.4 Cuarta fase: activar DEFAULT_SCHEMA solo a usuarios controlados

Marcar:

```text
DefaultSchema = true
Copiar permisos = true
```

solo para usuarios de reportería, auditoría limitada o soporte.

---

### 15.5 Quinta fase: política en DryRun

Opciones:

```text
ApplySafePolicy = true
DryRun = true
BaseAccessAction = REPORT_ONLY
```

Ejecutar.

Revisar logs y auditoría.

---

### 15.6 Sexta fase: política real sin bloqueo

Opciones:

```text
ApplySafePolicy = true
DryRun = false
BaseAccessAction = REPORT_ONLY
```

Esto debe:

```text
Aplicar DEFAULT_SCHEMA a usuarios seleccionados.
Copiar permisos hacia vistas.
No bloquear dbo todavía.
Respetar exclusiones.
```

---

### 15.7 Séptima fase: validar consultas

Probar como usuario:

```sql
EXECUTE AS USER = 'usuario_reportes';

SELECT * FROM Clientes;
SELECT * FROM masked.Clientes;
SELECT * FROM dbo.Clientes;

REVERT;
```

Validar que:

```text
SELECT * FROM Clientes use masked si existe.
masked.Clientes muestre datos ofuscados.
dbo.Clientes no se bloquee todavía si BaseAccessAction = REPORT_ONLY.
```

---

### 15.8 Octava fase: endurecimiento opcional

Solo después de validar se puede evaluar:

```text
REVOKE_EXPLICIT_OBJECT_PERMISSIONS
```

o:

```text
DENY_BASE_FOR_POLICY_PRINCIPALS
```

No usar esto en primera prueba.

---

## 16. Ejemplo completo de laboratorio

### 16.1 Crear base

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

### 16.2 Crear usuario de prueba

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

### 16.3 Ejecutar herramienta

Primera ejecución:

```text
DryRun = true
ApplyDDM = true
CreateViews = true
ApplySafePolicy = false
MaskingMode = HYBRID
```

Segunda ejecución:

```text
DryRun = false
ApplyDDM = true
CreateViews = true
ApplySafePolicy = false
```

---

### 16.4 Validar objetos

```sql
USE OfuscadorTest;
GO

SELECT * FROM dbo.Masked_Config;
SELECT TOP 100 * FROM dbo.Masked_Audit ORDER BY AuditId DESC;
SELECT * FROM dbo.Masked_Patterns;
```

Validar vistas:

```sql
SELECT 
    s.name AS SchemaName,
    v.name AS ViewName
FROM sys.views v
INNER JOIN sys.schemas s 
    ON v.schema_id = s.schema_id
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

### 16.5 Aplicar política al usuario

Agregar `masked_reader` en pantalla de usuarios:

```text
Activo = true
DefaultSchema = true
Copiar permisos = true
Incluir DML = false
Bloquear dbo = false
Excluir = false
Notas = Usuario de prueba para masked
```

Opciones:

```text
ApplySafePolicy = true
DryRun = true
BaseAccessAction = REPORT_ONLY
```

Ejecutar.

Luego:

```text
DryRun = false
```

Ejecutar.

---

### 16.6 Validar DEFAULT_SCHEMA

```sql
USE OfuscadorTest;
GO

SELECT name, default_schema_name
FROM sys.database_principals
WHERE name = 'masked_reader';
```

Probar:

```sql
EXECUTE AS USER = 'masked_reader';

SELECT * FROM Clientes;
SELECT * FROM masked.Clientes;
SELECT * FROM dbo.Clientes;

REVERT;
```

---

## 17. Troubleshooting

### 17.1 Error 26 al conectar

Causa típica:

```text
Servidor o instancia incorrecta.
```

Ejemplo incorrecto:

```text
Host = GINEBRA
Instancia = GINEBRA
```

Eso intenta:

```text
GINEBRA\GINEBRA
```

Si en SSMS te conectas con:

```text
GINEBRA
```

en la herramienta usa:

```text
Host = GINEBRA
Instancia = vacío
```

Si en SSMS usas:

```text
GINEBRA\SQLEXPRESS
```

usa:

```text
Host = GINEBRA
Instancia = SQLEXPRESS
```

---

### 17.2 Error de login

Si el servidor sí responde pero falla login:

```text
Usuario incorrecto.
Contraseña incorrecta.
SQL Authentication no habilitado.
Login deshabilitado.
Usuario sin acceso a la base.
```

---

### 17.3 Error de certificado

Para laboratorio:

```text
Encrypt = false
TrustServerCertificate = true
```

Para producción:

```text
Encrypt = true
Certificado válido
```

---

### 17.4 No aparecen usuarios

Verificar:

```text
Seleccionaste base.
La conexión tiene permisos para consultar sys.database_principals.
Existen usuarios creados en la base.
No todos están excluidos por filtros.
```

---

### 17.5 DEFAULT_SCHEMA no cambia

Verificar:

```text
ApplySafePolicy = true
ApplyDefaultSchema = true
DryRun = false
Usuario no está excluido
Usuario no es db_owner
Usuario no es sysadmin
Existe esquema masked
```

Consulta:

```sql
SELECT name, default_schema_name
FROM sys.database_principals
WHERE name = 'usuario';
```

---

### 17.6 SELECT sin esquema no usa masked

Causas:

```text
Usuario no tiene DEFAULT_SCHEMA = masked.
No existe masked.Tabla.
No tiene permiso sobre masked.Tabla.
La consulta usa dbo.Tabla explícitamente.
El usuario es sysadmin/db_owner.
```

---

### 17.7 Usuario excluido sí fue modificado

Esto no debería pasar.

Revisar:

```sql
SELECT *
FROM dbo.Masked_PrincipalExclusions
WHERE PrincipalName = 'usuario'
  AND IsEnabled = 1;
```

También revisar auditoría:

```sql
SELECT TOP 100 *
FROM dbo.Masked_Audit
ORDER BY AuditId DESC;
```

---

## 18. Buenas prácticas

### 18.1 Siempre usar DryRun

Primera ejecución:

```text
DryRun = true
```

---

### 18.2 No bloquear dbo al inicio

Usar:

```text
BaseAccessAction = REPORT_ONLY
```

---

### 18.3 Excluir cuentas críticas

Antes de aplicar política, excluir:

```text
ETL
Aplicaciones
Integraciones
Administradores
Mantenimiento
Monitoreo
```

---

### 18.4 No aplicar DefaultSchema masivo sin revisar

Aunque la prioridad sea `masked`, no todos los usuarios deben recibirlo.

Revisar usuario por usuario o rol por rol.

---

### 18.5 Usar roles cuando sea posible

En vez de aplicar a 100 usuarios individuales, puede ser mejor aplicar a un rol:

```text
rol_reporteria_masked
```

y administrar miembros de ese rol.

---

### 18.6 Revisar falsos positivos

Columnas como:

```text
Nombre
Descripcion
Observacion
Codigo
Referencia
```

pueden no ser sensibles en todas las tablas.

---

## 19. Checklist antes de producción

```text
[ ] Se probó en laboratorio.
[ ] Se ejecutó DryRun.
[ ] Se revisó dbo.Masked_Audit.
[ ] Se validaron columnas detectadas.
[ ] Se agregaron excepciones.
[ ] Se agregaron reglas manuales.
[ ] Se validó modo HYBRID.
[ ] Se crearon vistas masked.
[ ] Se validó DDM.
[ ] Se cargaron usuarios/roles con permisos.
[ ] Se excluyeron cuentas críticas.
[ ] Se aplicó DEFAULT_SCHEMA solo a usuarios controlados.
[ ] Se copió permisos a vistas.
[ ] Se mantuvo BaseAccessAction = REPORT_ONLY inicialmente.
[ ] Se validaron consultas como usuario final.
[ ] No se aplicó DENY sin autorización.
[ ] Existe plan de rollback.
```

---

## 20. Plan de rollback conceptual

### 20.1 Quitar DEFAULT_SCHEMA

```sql
ALTER USER [usuario] WITH DEFAULT_SCHEMA = dbo;
```

---

### 20.2 Quitar permisos sobre vistas

```sql
REVOKE SELECT ON OBJECT::masked.Clientes FROM usuario;
```

---

### 20.3 Quitar vistas

```sql
DROP VIEW masked.Clientes;
```

---

### 20.4 Quitar DDM

```sql
ALTER TABLE dbo.Clientes
ALTER COLUMN Correo DROP MASKED;
```

---

### 20.5 Mantener auditoría

Recomendado mantener:

```text
dbo.Masked_Audit
```

para trazabilidad.

---

## 21. Mejoras futuras recomendadas

```text
Pantalla para administrar patrones.
Pantalla para excepciones.
Árbol visual servidor/base/tabla/columna.
Exportar reporte a Excel.
Generar script DryRun.
Comparación antes/después.
Modo rollback automático.
Validación de permisos efectivos.
Prueba integrada como usuario.
Panel de usuarios excluidos.
Importación desde CSV.
Exportación de política JSON.
Historial de ejecuciones.
Control de versiones de scripts.
```

---

## 22. Resumen final

OfuscadorTool V3 está pensado para aplicar enmascaramiento con mayor control:

```text
Detecta columnas sensibles.
Permite modo patrón, manual e híbrido.
Aplica DDM.
Crea vistas masked.
Prioriza masked usando DEFAULT_SCHEMA.
Copia permisos puntuales sin regalar accesos generales.
Permite cargar usuarios automáticamente.
Permite cargar usuarios con permisos existentes.
Permite excluir usuarios o roles que no deben tocarse.
Evita tocar db_owner y sysadmin.
Trabaja primero en DryRun.
Permite revisar auditoría antes de aplicar.
```

La lógica correcta para uso real es:

```text
1. Crear DDM y vistas.
2. Revisar columnas.
3. Cargar usuarios con permisos.
4. Excluir cuentas críticas.
5. Aplicar DEFAULT_SCHEMA solo a usuarios controlados.
6. Copiar permisos hacia vistas.
7. Mantener REPORT_ONLY.
8. Validar.
9. Solo después evaluar bloqueo de dbo.
```

---

## 23. Guía rápida

```text
1. Abrir OfuscadorTool.
2. Agregar servidor.
3. Probar conexión.
4. Cargar bases.
5. Seleccionar base de laboratorio.
6. Modo = HYBRID.
7. Activar ApplyDDM y CreateViews.
8. Mantener DryRun = true.
9. Ejecutar.
10. Revisar auditoría.
11. Ejecutar con DryRun = false.
12. Cargar usuarios con permisos.
13. Excluir cuentas críticas.
14. Marcar DefaultSchema solo a usuarios controlados.
15. Activar ApplySafePolicy.
16. Ejecutar DryRun.
17. Ejecutar real con REPORT_ONLY.
18. Validar consultas como usuario.
```

---

**Fin del manual V3.**
