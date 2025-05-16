-- Solo si tienes SQL Server 2016 o superior
WITH Partes AS (
    SELECT 
        Cuenta,
        LEFT(Cuenta, CHARINDEX('-', Cuenta) - 1) AS Parte1,
        SUBSTRING(Cuenta, 
                  CHARINDEX('-', Cuenta) + 1, 
                  CHARINDEX('-', Cuenta, CHARINDEX('-', Cuenta) + 1) - CHARINDEX('-', Cuenta) - 1) AS Parte2,
        RIGHT(Cuenta, LEN(Cuenta) - CHARINDEX('-', Cuenta, CHARINDEX('-', Cuenta) + 1)) AS Parte3
    FROM Cuentas
    WHERE 
        Cuenta NOT LIKE '%[^0-9-]%' AND
        LEN(Cuenta) - LEN(REPLACE(Cuenta, '-', '')) = 2 AND
        CHARINDEX('-', Cuenta) > 1 AND
        RIGHT(Cuenta, 1) <> '-'
)
SELECT 
    Cuenta,
    CASE
        WHEN LEN(Parte1) <= 3 AND LEN(Parte2) <= 7 AND LEN(Parte3) = 1
            THEN 'Formato válido'
        ELSE 'Excede el formato XXX-XXXXXXX-X'
    END AS Resultado
FROM Partes;