
DECLARE @LinkedServerName NVARCHAR(255) = N'CALEL'; 

DECLARE @ServerCollation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;
DECLARE @OpenquerySQL NVARCHAR(MAX);
DECLARE @SQL NVARCHAR(MAX);
DECLARE @TBL_Tablas AS TABLE(ID INT IDENTITY(1, 1), [SCHEMA] VARCHAR(255), [NAME] VARCHAR(MAX))
DECLARE @TBL_Database AS TABLE(ID INT IDENTITY(1, 1), [NAME] VARCHAR(MAX), SERVIDOR VARCHAR(MAX))
DECLARE @TBL_LinkedServers AS TABLE(ID INT IDENTITY(1, 1), SRV_NAME VARCHAR(MAX), SRV_PROVIDERNAME VARCHAR(MAX), SRV_PRODUCT VARCHAR(MAX), SRV_DATASOURCE VARCHAR(MAX), 
                                    SRV_PROVIDERSTRING  VARCHAR(MAX), SRV_LOCATION  VARCHAR(MAX), SRV_CAT  VARCHAR(MAX))

INSERT INTO @TBL_LinkedServers (SRV_NAME, SRV_PROVIDERNAME, SRV_PRODUCT, SRV_DATASOURCE, SRV_PROVIDERSTRING, SRV_LOCATION, SRV_CAT)
EXEC sp_linkedservers

DECLARE @LsContador INT = (SELECT COUNT(1) FROM @TBL_LinkedServers);
DECLARE @LsIndex INT = 1;

WHILE @LsIndex <= @LsContador
BEGIN
    SELECT @ServerName = SRV_NAME FROM @TBL_LinkedServers WHERE ID = @LsIndex;

    SET @SQL  = N'';
    SET @SQL += N' SELECT name, @@SERVERNAME FROM sys.databases ';
    SET @SQL = REPLACE(@SQL, '''', '''''');

    SET @OpenquerySQL = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@ServerName) + N', ''' + @SQL + N''')';

    INSERT INTO @TBL_Database
    EXEC (@OpenquerySQL);

    SET @LsIndex += 1;
END

--SELECT * FROM @TBL_Database

DECLARE @BaseCount INT = (SELECT COUNT(1) FROM @TBL_Database);
DECLARE @BaseIndex INT = 1;
DECLARE @DatabaseName NVARCHAR(255);
DECLARE @TableName NVARCHAR(255);

WHILE @BaseIndex <= @BaseCount
BEGIN
    SELECT @DatabaseName = [NAME] FROM @TBL_Database WHERE ID = @BaseIndex;

    -- Obtenemos las tablas de esta base y las guardamos en otra tabla temporal
    IF OBJECT_ID('tempdb..#TablasRemotas') IS NOT NULL DROP TABLE #TablasRemotas;
    CREATE TABLE #TablasRemotas (ID INT IDENTITY(1,1), TableFullName NVARCHAR(255));

    SET @SQL  = N'';
    SET @SQL += N' SELECT TABLE_SCHEMA, TABLE_NAME FROM ' + QUOTENAME(@DatabaseName) + 'INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = ''BASE TABLE'' ';
    SET @SQL = REPLACE(@SQL, '''', '''''');

    SET @OpenquerySQL = N'SELECT TABLE_SCHEMA + ''.'' + TABLE_NAME FROM OPENQUERY(' + QUOTENAME(@ServerName) + N', ''' + @SQL + N''')';

    INSERT INTO #TablasRemotas (TableFullName)
    EXEC (@OpenquerySQL);

    -- Contador para recorrer #TablasRemotas
    DECLARE @TableCount INT = (SELECT COUNT(1) FROM #TablasRemotas);
    DECLARE @TableIndex INT = 1;

    WHILE @TableIndex <= @TableCount
    BEGIN
        SELECT @TableName = TableFullName FROM #TablasRemotas WHERE ID = @TableIndex;

        -- Aquí defines la consulta que quieres ejecutar para cada tabla
        SET @SQL = N'
        SELECT * 
        FROM OPENQUERY([' + @LinkedServerName + '], 
            ''SELECT * FROM ' + QUOTENAME(@DatabaseName) + '.' + @TableName + ''')';

        PRINT @SQL;  -- Muestra la consulta (puedes quitarlo)
        -- EXEC sp_executesql @SQL;  -- Descomenta para ejecutar

        SET @TableIndex += 1;
    END

    DROP TABLE #TablasRemotas;  -- Limpia tabla temporal de tablas

    SET @BaseIndex += 1;
END
