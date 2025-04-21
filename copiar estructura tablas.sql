-- Comentario: Este script genera un script CREATE TABLE para copiar la estructura de una tabla existente.
-- Reemplaza 'NombreDeLaTablaExistente' con el nombre de la tabla que deseas copiar
-- y 'NuevaTablaCopiaEstructura' con el nombre que deseas para la nueva tabla.

-- Indica la base de datos donde reside la tabla existente (opcional si ya estás conectado)
USE NombreDeLaBaseDeDatos;
GO

-- Genera el script CREATE TABLE para la tabla existente
SELECT
    'CREATE TABLE NuevaTablaCopiaEstructura ('
    + STRING_AGG(
        QUOTENAME(COLUMN_NAME) + ' ' + DATA_TYPE +
        CASE
            WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            WHEN NUMERIC_PRECISION IS NOT NULL AND NUMERIC_SCALE IS NOT NULL THEN '(' + CAST(NUMERIC_PRECISION AS VARCHAR(10)) + ',' + CAST(NUMERIC_SCALE AS VARCHAR(10)) + ')'
            WHEN DATETIME_PRECISION IS NOT NULL THEN '(' + CAST(DATETIME_PRECISION AS VARCHAR(10)) + ')'
            ELSE ''
        END +
        CASE
            WHEN IS_NULLABLE = 'NO' THEN ' NOT NULL'
            ELSE ' NULL'
        END +
        CASE
            WHEN COLUMN_DEFAULT IS NOT NULL THEN ' DEFAULT ' + COLUMN_DEFAULT
            ELSE ''
        END,
        ', ' + CHAR(13) + CHAR(10)
    )
    + ISNULL((SELECT ', ' + CHAR(13) + CHAR(10) +
                     'CONSTRAINT ' + QUOTENAME(tc.CONSTRAINT_NAME) + ' PRIMARY KEY (' +
                     STRING_AGG(QUOTENAME(kcu.COLUMN_NAME), ', ') WITHIN GROUP (ORDER BY kcu.ORDINAL_POSITION) + ')'
              FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
              INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                  ON tc.CONSTRAINT_CATALOG = kcu.CONSTRAINT_CATALOG
                  AND tc.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA
                  AND tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                  AND tc.TABLE_CATALOG = kcu.TABLE_CATALOG
                  AND tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
                  AND tc.TABLE_NAME = kcu.TABLE_NAME
              WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
                AND tc.TABLE_NAME = 'NombreDeLaTablaExistente'
              ), '')
    + ISNULL((SELECT ', ' + CHAR(13) + CHAR(10) +
                     'CONSTRAINT ' + QUOTENAME(fk.CONSTRAINT_NAME) + ' FOREIGN KEY (' + QUOTENAME(kcu.COLUMN_NAME) + ') ' +
                     'REFERENCES ' + QUOTENAME(referenced_table_name) + '(' + QUOTENAME(referenced_column_name) + ')' +
                     CASE
                         WHEN fk.delete_referential_action <> 'NO ACTION' THEN ' ON DELETE ' + fk.delete_referential_action
                         ELSE ''
                     END +
                     CASE
                         WHEN fk.update_referential_action <> 'NO ACTION' THEN ' ON UPDATE ' + fk.update_referential_action
                         ELSE ''
                     END
              FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS fk
              INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                  ON fk.CONSTRAINT_CATALOG = kcu.CONSTRAINT_CATALOG
                  AND fk.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA
                  AND fk.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                  AND kcu.ORDINAL_POSITION = 1 -- Asegura que solo se tome la columna de la clave foránea
              INNER JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc ON fk.UNIQUE_CONSTRAINT_CATALOG = tc.CONSTRAINT_CATALOG
                                                              AND fk.UNIQUE_CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
                                                              AND fk.UNIQUE_CONSTRAINT_NAME = tc.CONSTRAINT_NAME
              INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu_referenced
                  ON tc.CONSTRAINT_CATALOG = kcu_referenced.CONSTRAINT_CATALOG
                  AND tc.CONSTRAINT_SCHEMA = kcu_referenced.CONSTRAINT_SCHEMA
                  AND tc.CONSTRAINT_NAME = kcu_referenced.CONSTRAINT_NAME
                  AND kcu_referenced.ORDINAL_POSITION = 1
              WHERE kcu.TABLE_NAME = 'NombreDeLaTablaExistente'
              ), '')
    + ISNULL((SELECT ', ' + CHAR(13) + CHAR(10) +
                     'CONSTRAINT ' + QUOTENAME(tc.CONSTRAINT_NAME) + ' UNIQUE (' +
                     STRING_AGG(QUOTENAME(kcu.COLUMN_NAME), ', ') WITHIN GROUP (ORDER BY kcu.ORDINAL_POSITION) + ')'
              FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
              INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                  ON tc.CONSTRAINT_CATALOG = kcu.CONSTRAINT_CATALOG
                  AND tc.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA
                  AND tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                  AND tc.TABLE_CATALOG = kcu.TABLE_CATALOG
                  AND tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
                  AND tc.TABLE_NAME = kcu.TABLE_NAME
              WHERE tc.CONSTRAINT_TYPE = 'UNIQUE'
                AND tc.TABLE_NAME = 'NombreDeLaTablaExistente'
              ), '')
    + ISNULL((SELECT ', ' + CHAR(13) + CHAR(10) +
                     'CONSTRAINT ' + QUOTENAME(tc.CONSTRAINT_NAME) + ' CHECK (' + ck.CHECK_CLAUSE + ')'
              FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
              INNER JOIN INFORMATION_SCHEMA.CHECK_CONSTRAINTS ck
                  ON tc.CONSTRAINT_CATALOG = ck.CONSTRAINT_CATALOG
                  AND tc.CONSTRAINT_SCHEMA = ck.CONSTRAINT_SCHEMA
                  AND tc.CONSTRAINT_NAME = ck.CONSTRAINT_NAME
              WHERE tc.CONSTRAINT_TYPE = 'CHECK'
                AND tc.TABLE_NAME = 'NombreDeLaTablaExistente'
              ), '')
    + ');'
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'NombreDeLaTablaExistente'
ORDER BY ORDINAL_POSITION;
GO
