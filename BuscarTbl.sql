-- Ingresa el nombre de la tabla que deseas buscar
DECLARE @TableName NVARCHAR(255) = 'TuTabla';

-- Busca la tabla en todas las bases de datos
SELECT
    d.name AS DatabaseName,
    s.name AS SchemaName,
    o.name AS TableName
FROM
    sys.databases d
CROSS APPLY
    (SELECT name, schema_id FROM sys.objects WHERE type = 'U' AND name = @TableName) o
INNER JOIN
    sys.schemas s ON o.schema_id = s.schema_id
WHERE
    o.name IS NOT NULL
ORDER BY
    DatabaseName, SchemaName, TableName;
