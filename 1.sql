SELECT 
    DB_NAME(database_id) AS DatabaseName,
    name AS LogicalFileName,
    physical_name AS FilePath,
    size * 8 / 1024 AS SizeMB,
    CASE is_percent_growth 
        WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '%' 
        ELSE CAST(growth * 8 / 1024 AS VARCHAR(10)) + ' MB' 
    END AS GrowthSetting
FROM sys.master_files
WHERE type_desc = 'ROWS';  -- Solo Data (MDF/NDF)