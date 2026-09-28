SELECT 
    t.name AS table_name,
    p.rows AS [row_count]
FROM sys.tables t
INNER JOIN sys.partitions p 
    ON t.object_id = p.object_id 
    AND p.index_id IN (0, 1)
ORDER BY t.name;