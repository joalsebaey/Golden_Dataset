-- =====================================================================
-- 02_load_data.sql - SQL Server Data Import + Foreign Key Finalization
-- Expected Total Records: 500,526 rows across 8 tables
--
-- PREREQUISITE: Run 01_ddl.sql first (creates tables WITHOUT foreign keys).
--
-- Two ways to load the CSVs:
--   Option A (GUI): Import all 8 CSVs in ANY order using DBeaver Data Transfer
--                   wizard (set "Empty strings to NULL" = checked, UTF-8) or
--                   SSMS Import Flat File, then run STEP 2 onward below.
--   Option B (T-SQL BULK INSERT): Uncomment STEP 1 below, set @data_dir to your
--                   local dataset folder path, and run the whole script.
-- =====================================================================

-- =====================================================================
-- STEP 1 (OPTIONAL - T-SQL BULK INSERT):
-- If you already imported via DBeaver / SSMS wizard, skip to STEP 2.
-- =====================================================================
/*
DECLARE @data_dir NVARCHAR(500) = N'C:\path\to\multi_engine_sql_scripts\dataset';
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'BULK INSERT departments FROM ''' + @data_dir + N'\departments.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT roles FROM ''' + @data_dir + N'\roles.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT employees FROM ''' + @data_dir + N'\employees.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT employee_bank_accounts FROM ''' + @data_dir + N'\employee_bank_accounts.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT attendance FROM ''' + @data_dir + N'\attendance.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT role_permissions FROM ''' + @data_dir + N'\role_permissions.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT commissions FROM ''' + @data_dir + N'\commissions.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;

SET @sql = N'BULK INSERT employee_kpis FROM ''' + @data_dir + N'\employee_kpis.csv'' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPIDENTITY, KEEPNULLS, CODEPAGE = ''65001'', TABLOCK);';
EXEC sp_executesql @sql;
*/

-- =====================================================================
-- STEP 1.5: NORMALIZE EMPTY STRINGS FROM GUI IMPORTERS & ADD ATTENDANCE CHECKS
-- DBeaver's CSV importer inserts '' instead of NULL for empty VARCHAR cells
-- unless configured otherwise. Convert '' -> NULL and enforce strict CHECKs.
-- =====================================================================
UPDATE attendance SET work_mode = NULL WHERE LTRIM(RTRIM(work_mode)) = N'';

IF OBJECT_ID('chk_att_mode', 'C') IS NOT NULL ALTER TABLE attendance DROP CONSTRAINT chk_att_mode;
IF OBJECT_ID('chk_att_status_consistency', 'C') IS NOT NULL ALTER TABLE attendance DROP CONSTRAINT chk_att_status_consistency;

ALTER TABLE attendance ADD CONSTRAINT chk_att_mode
    CHECK (work_mode IS NULL OR work_mode IN ('onsite', 'remote', 'hybrid'));

ALTER TABLE attendance ADD CONSTRAINT chk_att_status_consistency
    CHECK (
        (status = 'present' AND hours_worked IS NOT NULL AND work_mode IS NOT NULL) OR
        (status <> 'present' AND hours_worked IS NULL AND work_mode IS NULL)
    );
GO

-- =====================================================================
-- STEP 2: PRE-FLIGHT ORPHAN CHECK (Every orphan_rows value must be 0)
-- =====================================================================
SELECT relationship, orphan_rows,
       CASE WHEN orphan_rows = 0 THEN 'OK' ELSE 'FIX DATA BEFORE STEP 4' END AS status
FROM (
    SELECT 'roles.department_id -> departments' AS relationship, COUNT(*) AS orphan_rows
    FROM roles c LEFT JOIN departments p ON c.department_id = p.department_id WHERE p.department_id IS NULL
    UNION ALL
    SELECT 'employees.department_id -> departments', COUNT(*)
    FROM employees c LEFT JOIN departments p ON c.department_id = p.department_id WHERE p.department_id IS NULL
    UNION ALL
    SELECT 'employees.role_id -> roles', COUNT(*)
    FROM employees c LEFT JOIN roles p ON c.role_id = p.role_id WHERE p.role_id IS NULL
    UNION ALL
    SELECT 'employees.manager_id -> employees', COUNT(*)
    FROM employees c LEFT JOIN employees p ON c.manager_id = p.employee_id WHERE c.manager_id IS NOT NULL AND p.employee_id IS NULL
    UNION ALL
    SELECT 'employee_bank_accounts.employee_id -> employees', COUNT(*)
    FROM employee_bank_accounts c LEFT JOIN employees p ON c.employee_id = p.employee_id WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'attendance.employee_id -> employees', COUNT(*)
    FROM attendance c LEFT JOIN employees p ON c.employee_id = p.employee_id WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'role_permissions.role_id -> roles', COUNT(*)
    FROM role_permissions c LEFT JOIN roles p ON c.role_id = p.role_id WHERE p.role_id IS NULL
    UNION ALL
    SELECT 'commissions.employee_id -> employees', COUNT(*)
    FROM commissions c LEFT JOIN employees p ON c.employee_id = p.employee_id WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'employee_kpis.employee_id -> employees', COUNT(*)
    FROM employee_kpis c LEFT JOIN employees p ON c.employee_id = p.employee_id WHERE p.employee_id IS NULL
) chk
ORDER BY relationship;
GO

-- =====================================================================
-- STEP 3: RESEED IDENTITY COUNTERS TO MAX LOADED IDs
-- =====================================================================
DECLARE @max_id BIGINT;
SELECT @max_id = ISNULL(MAX(department_id), 1)   FROM departments;            DBCC CHECKIDENT ('departments', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(role_id), 1)         FROM roles;                  DBCC CHECKIDENT ('roles', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(employee_id), 1)     FROM employees;              DBCC CHECKIDENT ('employees', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(bank_account_id), 1) FROM employee_bank_accounts; DBCC CHECKIDENT ('employee_bank_accounts', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(attendance_id), 1)   FROM attendance;             DBCC CHECKIDENT ('attendance', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(permission_id), 1)   FROM role_permissions;       DBCC CHECKIDENT ('role_permissions', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(commission_id), 1)   FROM commissions;            DBCC CHECKIDENT ('commissions', RESEED, @max_id);
SELECT @max_id = ISNULL(MAX(kpi_id), 1)          FROM employee_kpis;          DBCC CHECKIDENT ('employee_kpis', RESEED, @max_id);
GO

-- =====================================================================
-- STEP 4: ADD ALL 9 FOREIGN KEYS (Idempotent: drops first if present)
-- =====================================================================
IF OBJECT_ID('fk_roles_department', 'F')       IS NOT NULL ALTER TABLE roles                  DROP CONSTRAINT fk_roles_department;
IF OBJECT_ID('fk_employees_department', 'F')   IS NOT NULL ALTER TABLE employees              DROP CONSTRAINT fk_employees_department;
IF OBJECT_ID('fk_employees_role', 'F')         IS NOT NULL ALTER TABLE employees              DROP CONSTRAINT fk_employees_role;
IF OBJECT_ID('fk_employees_manager', 'F')      IS NOT NULL ALTER TABLE employees              DROP CONSTRAINT fk_employees_manager;
IF OBJECT_ID('fk_bank_accounts_employee', 'F') IS NOT NULL ALTER TABLE employee_bank_accounts DROP CONSTRAINT fk_bank_accounts_employee;
IF OBJECT_ID('fk_attendance_employee', 'F')    IS NOT NULL ALTER TABLE attendance             DROP CONSTRAINT fk_attendance_employee;
IF OBJECT_ID('fk_role_permissions_role', 'F')  IS NOT NULL ALTER TABLE role_permissions       DROP CONSTRAINT fk_role_permissions_role;
IF OBJECT_ID('fk_commissions_employee', 'F')   IS NOT NULL ALTER TABLE commissions            DROP CONSTRAINT fk_commissions_employee;
IF OBJECT_ID('fk_employee_kpis_employee', 'F') IS NOT NULL ALTER TABLE employee_kpis          DROP CONSTRAINT fk_employee_kpis_employee;

ALTER TABLE roles
    ADD CONSTRAINT fk_roles_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id);

ALTER TABLE employees
    ADD CONSTRAINT fk_employees_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id);

ALTER TABLE employees
    ADD CONSTRAINT fk_employees_role
    FOREIGN KEY (role_id) REFERENCES roles(role_id);

ALTER TABLE employees
    ADD CONSTRAINT fk_employees_manager
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id);

ALTER TABLE employee_bank_accounts
    ADD CONSTRAINT fk_bank_accounts_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE attendance
    ADD CONSTRAINT fk_attendance_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE role_permissions
    ADD CONSTRAINT fk_role_permissions_role
    FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE;

ALTER TABLE commissions
    ADD CONSTRAINT fk_commissions_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE employee_kpis
    ADD CONSTRAINT fk_employee_kpis_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;
GO

-- =====================================================================
-- STEP 5: ADD SALES-ONLY COMMISSION TRIGGER
-- =====================================================================
CREATE OR ALTER TRIGGER trg_employees_commission_sales_only
ON employees
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN departments d ON i.department_id = d.department_id
        WHERE i.commission_pct > 0 AND d.department_name <> 'Sales'
    )
    BEGIN
        RAISERROR ('commission_pct > 0 is allowed only for employees in the Sales department.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO

-- =====================================================================
-- STEP 6: VERIFICATION (Row Counts & Foreign Keys)
-- =====================================================================
SELECT table_name, loaded_rows, expected_rows,
       CASE WHEN loaded_rows = expected_rows THEN 'PASS' ELSE 'FAIL' END AS audit_status
FROM (
    SELECT 'departments'            AS table_name, COUNT(*) AS loaded_rows, 10     AS expected_rows FROM departments
    UNION ALL SELECT 'roles',                  COUNT(*), 43     FROM roles
    UNION ALL SELECT 'employees',              COUNT(*), 5000   FROM employees
    UNION ALL SELECT 'employee_bank_accounts', COUNT(*), 5000   FROM employee_bank_accounts
    UNION ALL SELECT 'attendance',             COUNT(*), 324449 FROM attendance
    UNION ALL SELECT 'role_permissions',       COUNT(*), 125    FROM role_permissions
    UNION ALL SELECT 'commissions',            COUNT(*), 7304   FROM commissions
    UNION ALL SELECT 'employee_kpis',          COUNT(*), 158595 FROM employee_kpis
) audit
ORDER BY table_name;

SELECT OBJECT_NAME(parent_object_id) AS child_table,
       name                          AS constraint_name,
       OBJECT_NAME(referenced_object_id) AS parent_table
FROM sys.foreign_keys
ORDER BY 1, 2;
GO
