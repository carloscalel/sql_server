-- Ingresa el nombre de la tabla que deseas buscar
DECLARE @TableName NVARCHAR(255) = 'TuTabla';

-- Busca la tabla en todas las bases de datos
SELECT
    DB_NAME(database_id) AS DatabaseName,
    SCHEMA_NAME(schema_id) AS SchemaName,
    name AS TableName
FROM
    sys.databases
CROSS APPLY
    sys.dm_db_objects(database_id)
WHERE
    type = 'U' -- 'U' indica tablas definidas por el usuario
    AND name = @TableName
ORDER BY
    DatabaseName, SchemaName, TableName;
