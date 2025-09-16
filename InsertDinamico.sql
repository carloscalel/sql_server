CREATE PROCEDURE sp_TrasladarDatos
    @Tabla NVARCHAR(128),
    @Filtro NVARCHAR(MAX) = NULL
AS
BEGIN
    DECLARE @Columnas NVARCHAR(MAX);
    DECLARE @SQL NVARCHAR(MAX);

    -- 1. Construir lista de columnas sin identity con STUFF
    SELECT @Columnas = STUFF((
        SELECT ', ' + QUOTENAME(c.name)
        FROM [ServidorOrigen].[BD].sys.columns c
        INNER JOIN [ServidorOrigen].[BD].sys.tables t ON c.object_id = t.object_id
        WHERE t.name = @Tabla
          AND c.is_identity = 0
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)')
    ,1,2,'');

    -- 2. Armar SQL dinámico
    SET @SQL = '
    INSERT INTO [ServidorDestino].[BD].[dbo].' + QUOTENAME(@Tabla) + '(' + @Columnas + ')
    SELECT ' + @Columnas + '
    FROM [ServidorOrigen].[BD].[dbo].' + QUOTENAME(@Tabla);

    -- 3. Agregar filtro si existe
    IF @Filtro IS NOT NULL AND LTRIM(RTRIM(@Filtro)) <> ''
        SET @SQL += ' WHERE ' + @Filtro;

    -- 4. Ejecutar
    EXEC sp_executesql @SQL;
END