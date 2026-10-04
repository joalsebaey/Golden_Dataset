-- =====================================================================
-- 02_load_data.sql - SQL Server Data Ingestion & Identity Synchronization
-- Loads all 8 canonical CSV datasets using parameterized BULK INSERT.
-- Expected Total Records: 500,526 rows across 8 tables
--
-- INSTRUCTIONS:
--   Set the @data_dir variable below to your local repository dataset directory path.
--   Ensure the SQL Server service account has read access to the specified folder.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Configuration: Specify Dataset Folder Path
-- ---------------------------------------------------------------------
DECLARE @data_dir NVARCHAR(500) = N'dataset'; 
-- If running against a remote/local instance requiring absolute paths, set accordingly:
-- e.g.: DECLARE @data_dir NVARCHAR(500) = N'C:\path\to\multi_engine_sql_scripts\dataset';

-- ---------------------------------------------------------------------
-- 2. Disable Constraints and Triggers for Optimal Bulk Load Performance
-- ---------------------------------------------------------------------
ALTER TABLE employee_kpis          NOCHECK CONSTRAINT ALL;
ALTER TABLE commissions            NOCHECK CONSTRAINT ALL;
ALTER TABLE role_permissions       NOCHECK CONSTRAINT ALL;
ALTER TABLE attendance             NOCHECK CONSTRAINT ALL;
ALTER TABLE employee_bank_accounts NOCHECK CONSTRAINT ALL;
ALTER TABLE employees              NOCHECK CONSTRAINT ALL;
ALTER TABLE roles                  NOCHECK CONSTRAINT ALL;
ALTER TABLE departments            NOCHECK CONSTRAINT ALL;

-- Disable triggers on employees during bulk load
DISABLE TRIGGER trg_employees_commission_sales_only ON employees;
GO

-- ---------------------------------------------------------------------
-- 3. Execute BULK INSERT for Each Table
--    KEEPIDENTITY: Preserves exact primary key IDs from CSV files
--    KEEPNULLS:    Maps empty string CSV cells to database NULLs
--    CODEPAGE:     '65001' (UTF-8) ensures full Unicode Arabic fidelity
-- ---------------------------------------------------------------------
DECLARE @data_dir NVARCHAR(500) = N'dataset';
DECLARE @sql NVARCHAR(MAX);

-- 1/8 departments
PRINT '>>> [1/8] Loading departments (10 rows)...';
SET @sql = N'BULK INSERT departments FROM ''' + @data_dir + N'\departments.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 2/8 roles
PRINT '>>> [2/8] Loading roles (43 rows)...';
SET @sql = N'BULK INSERT roles FROM ''' + @data_dir + N'\roles.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 3/8 employees
PRINT '>>> [3/8] Loading employees (5,000 rows)...';
SET @sql = N'BULK INSERT employees FROM ''' + @data_dir + N'\employees.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 4/8 employee_bank_accounts
PRINT '>>> [4/8] Loading employee_bank_accounts (5,000 rows)...';
SET @sql = N'BULK INSERT employee_bank_accounts FROM ''' + @data_dir + N'\employee_bank_accounts.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 5/8 attendance
PRINT '>>> [5/8] Loading attendance (324,449 rows)...';
SET @sql = N'BULK INSERT attendance FROM ''' + @data_dir + N'\attendance.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 6/8 role_permissions
PRINT '>>> [6/8] Loading role_permissions (125 rows)...';
SET @sql = N'BULK INSERT role_permissions FROM ''' + @data_dir + N'\role_permissions.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 7/8 commissions
PRINT '>>> [7/8] Loading commissions (7,304 rows)...';
SET @sql = N'BULK INSERT commissions FROM ''' + @data_dir + N'\commissions.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

-- 8/8 employee_kpis
PRINT '>>> [8/8] Loading employee_kpis (158,595 rows)...';
SET @sql = N'BULK INSERT employee_kpis FROM ''' + @data_dir + N'\employee_kpis.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;
GO

-- ---------------------------------------------------------------------
-- 4. Re-enable Constraints and Triggers
-- ---------------------------------------------------------------------
ALTER TABLE departments            CHECK CONSTRAINT ALL;
ALTER TABLE roles                  CHECK CONSTRAINT ALL;
ALTER TABLE employees              CHECK CONSTRAINT ALL;
ALTER TABLE employee_bank_accounts CHECK CONSTRAINT ALL;
ALTER TABLE attendance             CHECK CONSTRAINT ALL;
ALTER TABLE role_permissions       CHECK CONSTRAINT ALL;
ALTER TABLE commissions            CHECK CONSTRAINT ALL;
ALTER TABLE employee_kpis          CHECK CONSTRAINT ALL;

ENABLE TRIGGER trg_employees_commission_sales_only ON employees;
GO

-- ---------------------------------------------------------------------
-- 5. Reseed Identity Counters to Current Maximum Values
-- ---------------------------------------------------------------------
DECLARE @max_id BIGINT;

SELECT @max_id = ISNULL(MAX(department_id), 1) FROM departments;
DBCC CHECKIDENT ('departments', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(role_id), 1) FROM roles;
DBCC CHECKIDENT ('roles', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(employee_id), 1) FROM employees;
DBCC CHECKIDENT ('employees', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(bank_account_id), 1) FROM employee_bank_accounts;
DBCC CHECKIDENT ('employee_bank_accounts', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(attendance_id), 1) FROM attendance;
DBCC CHECKIDENT ('attendance', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(permission_id), 1) FROM role_permissions;
DBCC CHECKIDENT ('role_permissions', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(commission_id), 1) FROM commissions;
DBCC CHECKIDENT ('commissions', RESEED, @max_id);

SELECT @max_id = ISNULL(MAX(kpi_id), 1) FROM employee_kpis;
DBCC CHECKIDENT ('employee_kpis', RESEED, @max_id);
GO

-- ---------------------------------------------------------------------
-- 6. Comprehensive Row Count Audit & Integrity Verification
-- ---------------------------------------------------------------------
SELECT 
    table_name,
    loaded_rows,
    expected_rows,
    CASE WHEN loaded_rows = expected_rows THEN 'PASS' ELSE 'FAIL' END AS audit_status
FROM (
    SELECT 'departments'            AS table_name, COUNT(*) AS loaded_rows, 10      AS expected_rows FROM departments
    UNION ALL
    SELECT 'roles',                                COUNT(*),               43                        FROM roles
    UNION ALL
    SELECT 'employees',                            COUNT(*),               5000                      FROM employees
    UNION ALL
    SELECT 'employee_bank_accounts',               COUNT(*),               5000                      FROM employee_bank_accounts
    UNION ALL
    SELECT 'attendance',                           COUNT(*),               324449                    FROM attendance
    UNION ALL
    SELECT 'role_permissions',                     COUNT(*),               125                       FROM role_permissions
    UNION ALL
    SELECT 'commissions',                          COUNT(*),               7304                      FROM commissions
    UNION ALL
    SELECT 'employee_kpis',                        COUNT(*),               158595                    FROM employee_kpis
) audit
ORDER BY table_name;
GO
