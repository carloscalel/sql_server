DECLARE @Cuenta VARCHAR(50) = '123-4567890-1';  -- Cambia esto para probar

DECLARE @Parte1 VARCHAR(10), @Parte2 VARCHAR(10), @Parte3 VARCHAR(10);

-- Solo si cumple estructura básica (2 guiones, no caracteres extraños)
IF @Cuenta NOT LIKE '%[^0-9-]%' 
   AND LEN(@Cuenta) - LEN(REPLACE(@Cuenta, '-', '')) = 2
   AND CHARINDEX('-', @Cuenta) > 1
   AND RIGHT(@Cuenta, 1) <> '-'
BEGIN
    -- Extraer partes
    SET @Parte1 = LEFT(@Cuenta, CHARINDEX('-', @Cuenta) - 1);
    
    SET @Parte2 = SUBSTRING(
        @Cuenta, 
        CHARINDEX('-', @Cuenta) + 1, 
        CHARINDEX('-', @Cuenta, CHARINDEX('-', @Cuenta) + 1) - CHARINDEX('-', @Cuenta) - 1
    );
    
    SET @Parte3 = RIGHT(@Cuenta, LEN(@Cuenta) - CHARINDEX('-', @Cuenta, CHARINDEX('-', @Cuenta) + 1));

    -- Validar tamaños de las partes
    IF LEN(@Parte1) <= 3 AND LEN(@Parte2) <= 7 AND LEN(@Parte3) = 1
        PRINT 'Formato válido';
    ELSE
        PRINT 'Excede el formato XXX-XXXXXXX-X';
END
ELSE
    PRINT 'Formato inválido (estructura incorrecta)';