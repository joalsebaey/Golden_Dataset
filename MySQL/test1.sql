SELECT 
    table_name, 
    table_rows AS estimated_row_count
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY table_name;