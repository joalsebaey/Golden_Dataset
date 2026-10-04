-- =====================================================================
-- 02_load_data.sql - PostgreSQL Data Import + Foreign Key Finalization
-- Expected Total Records: 500,526 rows across 8 tables
--
-- PREREQUISITE: Run 01_ddl.sql first (creates tables WITHOUT foreign keys).
--
-- This script is 100% plain SQL - it runs in DBeaver (Alt+X), pgAdmin, or psql.
-- It is safe to re-run: every step is idempotent.
-- =====================================================================

SET search_path TO public;

-- =====================================================================
-- STEP 1: IMPORT THE 8 CSV FILES  (do this BEFORE running the rest)
-- Because 01_ddl.sql has no foreign keys, the import ORDER DOES NOT MATTER.
-- =====================================================================
--
-- OPTION A - DBeaver Data Transfer wizard (all 8 files in ONE batch)
--   1. In Database Navigator: right-click  public > Tables  > Import Data
--   2. Choose "CSV", select all 8 files from the  dataset/  folder
--   3. Tables mapping: each CSV -> table with the SAME name, mapping = "existing"
--        departments.csv            -> departments
--        roles.csv                  -> roles
--        employees.csv              -> employees
--        employee_bank_accounts.csv -> employee_bank_accounts
--        attendance.csv             -> attendance
--        role_permissions.csv       -> role_permissions
--        commissions.csv            -> commissions
--        employee_kpis.csv          -> employee_kpis
--   4. Importer settings (IMPORTANT):
--        Encoding ............... UTF-8   (Arabic names)
--        Header ................. top
--        Column delimiter ....... ,
--        Quote char ............. "
--        Set empty strings to NULL  [x]  <-- REQUIRED (salary, manager_id,
--                                            termination_date, hours_worked,
--                                            attendance.work_mode are blank = NULL)
--   5. Click Proceed. Then run STEP 2 onward of this script (Alt+X).
--
-- OPTION B - psql command line (run from the repository root folder)
--   Copy these lines into psql, or save them in a .psql file:
--
--   \copy departments(department_id, department_name, budget_egp, location) FROM 'dataset/departments.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy roles(role_id, department_id, role_title, level, salary_band_min, salary_band_max) FROM 'dataset/roles.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy employees(employee_id, first_name, last_name, email, department_id, role_id, salary, commission_pct, hire_date, termination_date, is_active, work_mode, manager_id) FROM 'dataset/employees.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy employee_bank_accounts(bank_account_id, employee_id, bank_name, iban, account_number) FROM 'dataset/employee_bank_accounts.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy attendance(attendance_id, employee_id, work_date, status, hours_worked, work_mode) FROM 'dataset/attendance.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy role_permissions(permission_id, role_id, permission_name, access_level, is_allowed) FROM 'dataset/role_permissions.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy commissions(commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount) FROM 'dataset/commissions.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--   \copy employee_kpis(kpi_id, employee_id, period_month, kpi_name, target, actual, score) FROM 'dataset/employee_kpis.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');
--
-- If an import fails half-way: re-run 01_ddl.sql (empties all tables) and import again.
-- =====================================================================


-- =====================================================================
-- STEP 2: PRE-FLIGHT ORPHAN CHECK
-- Every orphan_rows value must be 0. If any is > 0, STEP 4 will fail and
-- this result tells you exactly which relationship / CSV is the problem.
-- =====================================================================
SELECT relationship, orphan_rows,
       CASE WHEN orphan_rows = 0 THEN 'OK' ELSE 'FIX DATA BEFORE STEP 4' END AS status
FROM (
    SELECT 'roles.department_id -> departments'                AS relationship,
           COUNT(*) AS orphan_rows
    FROM roles c LEFT JOIN departments p ON c.department_id = p.department_id
    WHERE p.department_id IS NULL
    UNION ALL
    SELECT 'employees.department_id -> departments', COUNT(*)
    FROM employees c LEFT JOIN departments p ON c.department_id = p.department_id
    WHERE p.department_id IS NULL
    UNION ALL
    SELECT 'employees.role_id -> roles', COUNT(*)
    FROM employees c LEFT JOIN roles p ON c.role_id = p.role_id
    WHERE p.role_id IS NULL
    UNION ALL
    SELECT 'employees.manager_id -> employees', COUNT(*)
    FROM employees c LEFT JOIN employees p ON c.manager_id = p.employee_id
    WHERE c.manager_id IS NOT NULL AND p.employee_id IS NULL
    UNION ALL
    SELECT 'employee_bank_accounts.employee_id -> employees', COUNT(*)
    FROM employee_bank_accounts c LEFT JOIN employees p ON c.employee_id = p.employee_id
    WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'attendance.employee_id -> employees', COUNT(*)
    FROM attendance c LEFT JOIN employees p ON c.employee_id = p.employee_id
    WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'role_permissions.role_id -> roles', COUNT(*)
    FROM role_permissions c LEFT JOIN roles p ON c.role_id = p.role_id
    WHERE p.role_id IS NULL
    UNION ALL
    SELECT 'commissions.employee_id -> employees', COUNT(*)
    FROM commissions c LEFT JOIN employees p ON c.employee_id = p.employee_id
    WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'employee_kpis.employee_id -> employees', COUNT(*)
    FROM employee_kpis c LEFT JOIN employees p ON c.employee_id = p.employee_id
    WHERE p.employee_id IS NULL
    UNION ALL
    SELECT 'employees: commission_pct > 0 outside Sales', COUNT(*)
    FROM employees e JOIN departments d ON e.department_id = d.department_id
    WHERE e.commission_pct > 0 AND d.department_name <> 'Sales'
) chk
ORDER BY relationship;


-- =====================================================================
-- STEP 3: SYNCHRONIZE SERIAL / BIGSERIAL SEQUENCES
-- CSV rows were imported with explicit IDs, so move each sequence to MAX(id).
-- Prevents duplicate-key errors on future INSERTs.
-- =====================================================================
SELECT setval(pg_get_serial_sequence('departments', 'department_id'),              COALESCE((SELECT MAX(department_id)   FROM departments), 1));
SELECT setval(pg_get_serial_sequence('roles', 'role_id'),                          COALESCE((SELECT MAX(role_id)         FROM roles), 1));
SELECT setval(pg_get_serial_sequence('employees', 'employee_id'),                  COALESCE((SELECT MAX(employee_id)     FROM employees), 1));
SELECT setval(pg_get_serial_sequence('employee_bank_accounts', 'bank_account_id'), COALESCE((SELECT MAX(bank_account_id) FROM employee_bank_accounts), 1));
SELECT setval(pg_get_serial_sequence('attendance', 'attendance_id'),               COALESCE((SELECT MAX(attendance_id)   FROM attendance), 1));
SELECT setval(pg_get_serial_sequence('role_permissions', 'permission_id'),         COALESCE((SELECT MAX(permission_id)   FROM role_permissions), 1));
SELECT setval(pg_get_serial_sequence('commissions', 'commission_id'),              COALESCE((SELECT MAX(commission_id)   FROM commissions), 1));
SELECT setval(pg_get_serial_sequence('employee_kpis', 'kpi_id'),                   COALESCE((SELECT MAX(kpi_id)          FROM employee_kpis), 1));


-- =====================================================================
-- STEP 4 + 5: ADD ALL FOREIGN KEYS AND THE BUSINESS-RULE TRIGGER
-- Runs as ONE transaction: either every constraint is added, or none are.
-- DROP ... IF EXISTS first makes the step safely re-runnable.
-- =====================================================================
BEGIN;

-- Level 1: roles -> departments
ALTER TABLE roles DROP CONSTRAINT IF EXISTS fk_roles_department;
ALTER TABLE roles
    ADD CONSTRAINT fk_roles_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id);

-- Level 2: employees -> departments, roles, and itself (manager hierarchy)
ALTER TABLE employees DROP CONSTRAINT IF EXISTS fk_employees_department;
ALTER TABLE employees
    ADD CONSTRAINT fk_employees_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id);

ALTER TABLE employees DROP CONSTRAINT IF EXISTS fk_employees_role;
ALTER TABLE employees
    ADD CONSTRAINT fk_employees_role
    FOREIGN KEY (role_id) REFERENCES roles(role_id);

ALTER TABLE employees DROP CONSTRAINT IF EXISTS fk_employees_manager;
ALTER TABLE employees
    ADD CONSTRAINT fk_employees_manager
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id);

-- Level 3: child tables -> employees / roles
ALTER TABLE employee_bank_accounts DROP CONSTRAINT IF EXISTS fk_bank_accounts_employee;
ALTER TABLE employee_bank_accounts
    ADD CONSTRAINT fk_bank_accounts_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE attendance DROP CONSTRAINT IF EXISTS fk_attendance_employee;
ALTER TABLE attendance
    ADD CONSTRAINT fk_attendance_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE role_permissions DROP CONSTRAINT IF EXISTS fk_role_permissions_role;
ALTER TABLE role_permissions
    ADD CONSTRAINT fk_role_permissions_role
    FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE;

ALTER TABLE commissions DROP CONSTRAINT IF EXISTS fk_commissions_employee;
ALTER TABLE commissions
    ADD CONSTRAINT fk_commissions_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE employee_kpis DROP CONSTRAINT IF EXISTS fk_employee_kpis_employee;
ALTER TABLE employee_kpis
    ADD CONSTRAINT fk_employee_kpis_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

-- Business rule trigger: commission_pct > 0 is allowed ONLY for the Sales department.
-- Created after import so it never blocks loading employees before departments.
CREATE OR REPLACE FUNCTION trg_commission_sales_only() RETURNS trigger AS $$
BEGIN
    IF NEW.commission_pct > 0 AND NOT EXISTS (
        SELECT 1 FROM departments d
        WHERE d.department_id = NEW.department_id AND d.department_name = 'Sales'
    ) THEN
        RAISE EXCEPTION 'commission_pct > 0 is allowed only for Sales employees (email=%)', NEW.email;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employees_commission_sales_only ON employees;
CREATE TRIGGER employees_commission_sales_only
    BEFORE INSERT OR UPDATE OF commission_pct, department_id ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_commission_sales_only();

COMMIT;

-- Refresh planner statistics after the bulk load
ANALYZE;


-- =====================================================================
-- STEP 6: VERIFICATION
-- =====================================================================

-- 6a) Row count audit - every row must show PASS
SELECT table_name, loaded_rows, expected_rows,
       CASE WHEN loaded_rows = expected_rows THEN 'PASS' ELSE 'FAIL' END AS status
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

-- 6b) Foreign keys now in place - expect 9 rows
SELECT conrelid::regclass  AS child_table,
       conname             AS constraint_name,
       confrelid::regclass AS parent_table
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'public'::regnamespace
ORDER BY 1, 2;
