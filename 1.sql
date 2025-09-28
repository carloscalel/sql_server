USE TuBaseDeDatos;
GO

SELECT 
    df.name AS LogicalFileName,
    df.physical_name AS FilePath,
    df.type_desc AS FileType,
    (df.size * 8) / 1024 AS FileSizeMB, -- Tamaño total en MB
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(10,2)) AS SpaceUsedMB, -- Usado
    ((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) * 8.0 / 1024) AS FreeSpaceMB, -- Libre
    CAST(100.0 * (df.size - FILEPROPERTY(df.name, 'SpaceUsed')) / df.size AS DECIMAL(5,2)) AS FreeSpacePct -- % Libre
FROM sys.database_files df
WHERE df.type_desc = 'ROWS'; -- Solo MDF/NDF



https://teams.microsoft.com/l/meetup-join/19%3ameeting_MjgyN2E2MDgtYzljMC00MjQxLWE2Y2ItNWY3Mjc0OGVkNmQ2%40thread.v2/0?context=%7b%22Tid%22%3a%224f1d8a3a-c21d-4415-9a3e-d743e350dc3c%22%2c%22Oid%22%3a%223ff34afa-9ec5-486d-bf1d-209101ca9113%22%7d