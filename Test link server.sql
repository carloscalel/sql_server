DECLARE @LinkedServerName NVARCHAR(128);
DECLARE @SQL NVARCHAR(MAX);

-- Asigna dinámicamente el nombre del Linked Server a la variable
SET @LinkedServerName = N'TuLinkedServer'; -- Reemplaza con el nombre de tu Linked Server

-- Construye la cadena SQL para ejecutar sp_testlinkedserver
SET @SQL = N'EXEC sp_testlinkedserver @servername = N''' + @LinkedServerName + '''';

-- Ejecuta el SQL dinámico
BEGIN TRY
    EXEC sp_executesql @SQL;
    PRINT 'Conexión exitosa a ' + @LinkedServerName;
END TRY
BEGIN CATCH
    PRINT 'Error al conectar a ' + @LinkedServerName;
    PRINT 'Mensaje de error: ' + ERROR_MESSAGE();
END CATCH;
