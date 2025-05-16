SELECT 
    Cuenta,
    CASE 
        WHEN 
            Cuenta LIKE '%[^0-9-]%'         -- Contiene algo que no es dígito ni guion
            OR LEN(Cuenta) - LEN(REPLACE(Cuenta, '-', '')) <> 2  -- No tiene exactamente 2 guiones
            OR CHARINDEX('-', Cuenta) = 1                         -- Primer carácter es guion
            OR RIGHT(Cuenta, 1) = '-'                             -- Último carácter es guion
        THEN 'Formato inválido'
        ELSE 'Formato válido'
    END AS Resultado
FROM Cuentas;