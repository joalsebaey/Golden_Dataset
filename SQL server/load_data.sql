-- =====================================================================
-- SQL Server / T-SQL Dataset Ingestion Script
-- Loads 8 governed CSV datasets using BULK INSERT
-- Expected Total Rows: ~500,526 rows across 8 tables
--
-- Prerequisites:
--   Update the @data_dir variable below to your local repository directory path,
--   or ensure files are accessible by the SQL Server service account.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Disable constraints and triggers for maximum bulk load performance
-- ---------------------------------------------------------------------
ALTER TABLE employee_kpis            NOCHECK CONSTRAINT ALL;
ALTER TABLE commissions              NOCHECK CONSTRAINT ALL;
ALTER TABLE role_permissions         NOCHECK CONSTRAINT ALL;
ALTER TABLE attendance               NOCHECK CONSTRAINT ALL;
ALTER TABLE employee_bank_accounts   NOCHECK CONSTRAINT ALL;
ALTER TABLE employees                NOCHECK CONSTRAINT ALL;
ALTER TABLE roles                    NOCHECK CONSTRAINT ALL;
ALTER TABLE departments              NOCHECK CONSTRAINT ALL;
GO

-- ---------------------------------------------------------------------
-- 2. Execute BULK INSERT for each table in FK dependency order
--    KEEPIDENTITY: Retains explicit identity IDs from CSV
--    KEEPNULLS:    Empty CSV fields are inserted as NULLs
--    CODEPAGE:     '65001' (UTF-8) ensures Arabic characters are preserved
-- ---------------------------------------------------------------------

-- Note: Adjust path if running against a remote SQL Server instance
PRINT '>>> 1/8 Loading departments...';
BULK INSERT departments
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\departments.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 2/8 Loading roles...';
BULK INSERT roles
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\roles.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 3/8 Loading employees (5,000 rows)...';
BULK INSERT employees
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\employees.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 4/8 Loading employee_bank_accounts (5,000 rows)...';
BULK INSERT employee_bank_accounts
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\employee_bank_accounts.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 5/8 Loading attendance (324,449 rows)...';
BULK INSERT attendance
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\attendance.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 6/8 Loading role_permissions (83 rows)...';
BULK INSERT role_permissions
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\role_permissions.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 7/8 Loading commissions (7,304 rows)...';
BULK INSERT commissions
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\commissions.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

PRINT '>>> 8/8 Loading employee_kpis (141,310 rows)...';
BULK INSERT employee_kpis
FROM 'C:\Users\youse\Dropbox\PC\Downloads\golden database\dataset\employee_kpis.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    KEEPNULLS,
    CODEPAGE = '65001',
    TABLOCK
);
GO

-- ---------------------------------------------------------------------
-- 3. Re-enable and validate all constraints
-- ---------------------------------------------------------------------
ALTER TABLE departments            WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE roles                  WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE employees              WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE employee_bank_accounts WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE attendance             WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE role_permissions       WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE commissions            WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE employee_kpis          WITH CHECK CHECK CONSTRAINT ALL;
GO

-- ---------------------------------------------------------------------
-- 4. Verification & Row Count Audit
-- ---------------------------------------------------------------------
SELECT 'departments'            AS table_name, COUNT(*) AS loaded_rows, 10      AS expected_rows FROM departments
UNION ALL
SELECT 'roles',                                COUNT(*),               40                        FROM roles
UNION ALL
SELECT 'employees',                            COUNT(*),               5000                      FROM employees
UNION ALL
SELECT 'employee_bank_accounts',               COUNT(*),               5000                      FROM employee_bank_accounts
UNION ALL
SELECT 'attendance',                           COUNT(*),               324449                    FROM attendance
UNION ALL
SELECT 'role_permissions',                     COUNT(*),               83                        FROM role_permissions
UNION ALL
SELECT 'commissions',                          COUNT(*),               7304                      FROM commissions
UNION ALL
SELECT 'employee_kpis',                        COUNT(*),               141310                    FROM employee_kpis;
GO
