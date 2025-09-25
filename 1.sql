DECLARE 
    @database_size NVARCHAR(50),
    @unallocated_space NVARCHAR(50),
    @reserved NVARCHAR(50),
    @data NVARCHAR(50),
    @index_size NVARCHAR(50),
    @unused NVARCHAR(50);

-- Ejecutar sp_spaceused con variables OUTPUT
EXEC sp_spaceused 
     @updateusage = N'TRUE', 
     @database_size = @database_size OUTPUT, 
     @unallocated_space = @unallocated_space OUTPUT, 
     @reserved = @reserved OUTPUT, 
     @data = @data OUTPUT, 
     @index_size = @index_size OUTPUT, 
     @unused = @unused OUTPUT;

-- Ver resultados
SELECT 
    @database_size AS database_size,
    @unallocated_space AS unallocated_space,
    @reserved AS reserved,
    @data AS data,
    @index_size AS index_size,
    @unused AS unused;