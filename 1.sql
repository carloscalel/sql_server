DECLARE @LinkedServer sysname = N'CALEL';
DECLARE @DB          sysname = N'AdventureWorks2022';

DECLARE @RemoteBatch nvarchar(max) = N'
SET NOCOUNT ON;

DECLARE @spaceused TABLE
(
    [name]       sysname,
    [rows]       char(11),
    reserved     varchar(18),
    data         varchar(18),
    index_size   varchar(18),
    unused       varchar(18)
);

DECLARE @report TABLE
(
    schema_name sysname NOT NULL,
    table_name  sysname NOT NULL,
    rows_count  bigint  NULL,
    reserved_kb bigint  NULL,
    data_kb     bigint  NULL,
    index_kb    bigint  NULL,
    unused_kb   bigint  NULL
);

DECLARE @tables TABLE
(
    id int IDENTITY(1,1) PRIMARY KEY,
    schema_name sysname,
    table_name  sysname
);

INSERT INTO @tables(schema_name, table_name)
SELECT s.name, t.name
FROM ' + @DB + '.sys.tables t
JOIN ' + @DB + '.sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name;

DECLARE 
    @i int = 1,
    @max int,
    @schema sysname,
    @table sysname,
    @obj nvarchar(600);

SELECT @max = MAX(id) FROM @tables;

WHILE @i <= @max
BEGIN
    SELECT 
        @schema = schema_name,
        @table  = table_name
    FROM @tables
    WHERE id = @i;

    SET @obj = QUOTENAME(@schema) + N''.'' + QUOTENAME(@table);

    DELETE FROM @spaceused;

    INSERT INTO @spaceused
    EXEC ' + @DB + '.sys.sp_spaceused 
         @objname = @obj, 
         @updateusage = ''FALSE'';

    INSERT INTO @report(schema_name, table_name, rows_count, reserved_kb, data_kb, index_kb, unused_kb)
    SELECT
        @schema,
        @table,
        TRY_CONVERT(bigint, LTRIM(RTRIM([rows]))),
        TRY_CONVERT(bigint, REPLACE(reserved,   '' KB'','''')),
        TRY_CONVERT(bigint, REPLACE(data,       '' KB'','''')),
        TRY_CONVERT(bigint, REPLACE(index_size, '' KB'','''')),
        TRY_CONVERT(bigint, REPLACE(unused,     '' KB'',''''))
    FROM @spaceused;

    SET @i += 1;
END;

SELECT
    CONCAT(schema_name, ''.'', table_name) AS [Name],
    rows_count                             AS [Rows],
    reserved_kb                            AS [Reserved],
    data_kb                                AS [Data],
    index_kb                               AS [Index_Size],
    unused_kb                              AS [Unused]
FROM @report
ORDER BY reserved_kb DESC, Name;
';

DECLARE @OpenQuery nvarchar(max) =
N'SELECT *
  FROM OPENQUERY(' + QUOTENAME(@LinkedServer) + N', ''' + REPLACE(@RemoteBatch, '''', '''''') + N''');';

EXEC sys.sp_executesql @OpenQuery;

EXEC sp_spaceused 'Person.Person'
