
IF OBJECT_ID('tempdb..#ServidoresRemotos') IS NOT NULL DROP TABLE #ServidoresRemotos;
CREATE TABLE #ServidoresRemotos (
    ID INT IDENTITY(1,1),
    NombreServidor NVARCHAR(128)
);

INSERT INTO #ServidoresRemotos (NombreServidor)
VALUES ('CALEL'); 

-- Tabla de resultados
IF OBJECT_ID('tempdb..#ResultadoTablas') IS NOT NULL DROP TABLE #ResultadoTablas;
CREATE TABLE #ResultadoTablas (
    Servidor NVARCHAR(128),
    BaseDeDatos NVARCHAR(128),
    Esquema NVARCHAR(128),
    Tabla NVARCHAR(128)
);

CREATE CLUSTERED INDEX CIX_DatabaseTables
ON #ResultadoTablas (BaseDeDatos, Esquema, Tabla);

CREATE NONCLUSTERED INDEX IX_TableName
ON #ResultadoTablas (Tabla);

CREATE NONCLUSTERED INDEX IX_DatabaseName
ON #ResultadoTablas (BaseDeDatos);

-- Variables de control
DECLARE @lsIndex INT = 1, @bdIndex INT, @totalServidores INT, @totalBases INT;
DECLARE @Servidor NVARCHAR(128), @Base NVARCHAR(128), @SQL NVARCHAR(MAX);

SELECT @totalServidores = COUNT(1) FROM #ServidoresRemotos;

WHILE @lsIndex <= @totalServidores
BEGIN
    SELECT @Servidor = NombreServidor FROM #ServidoresRemotos WHERE ID = @lsIndex;

    -- Obtener bases de datos desde OPENQUERY
    IF OBJECT_ID('tempdb..#Bases') IS NOT NULL DROP TABLE #Bases;
    CREATE TABLE #Bases (
        ID INT IDENTITY(1,1),
        name NVARCHAR(128)
    );

    SET @SQL = '
        SELECT name 
        FROM OPENQUERY([' + @Servidor + '],
        ''SELECT name FROM sys.databases
          WHERE name NOT IN (''''master'''', ''''tempdb'''', ''''model'''', ''''msdb'''')'')';

    INSERT INTO #Bases (name)
    EXEC(@SQL);

    -- Recorrer bases
    SET @bdIndex = 1;
    SELECT @totalBases = COUNT(1) FROM #Bases;

    WHILE @bdIndex <= @totalBases
    BEGIN
        SELECT @Base = name FROM #Bases WHERE ID = @bdIndex;

        SET @SQL = '
            INSERT INTO #ResultadoTablas (Servidor, BaseDeDatos, Esquema, Tabla)
            SELECT servername, ''' + @Base + ''', schema_name, table_name
            FROM OPENQUERY([' + @Servidor + '],
            ''
                SELECT @@SERVERNAME servername,
                    s.name AS schema_name,
                    t.name AS table_name
                FROM [' + @Base + '].sys.tables t
                JOIN [' + @Base + '].sys.schemas s ON t.schema_id = s.schema_id
            '')
        ';
        
        EXEC(@SQL);

        SET @bdIndex += 1;
    END

    SET @lsIndex += 1;
END

-- Mostrar resultados
SELECT * 
FROM #ResultadoTablas
ORDER BY Servidor, BaseDeDatos, Esquema, Tabla;
