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



https://teams.microsoft.com/meet/220080073283?p=d8eOuxNLZAAiBhkSyq