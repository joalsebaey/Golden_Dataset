-- =====================================================================
-- 02_load_data.sql - PostgreSQL Data Ingestion & Sequence Synchronization
-- Loads all 8 canonical CSV datasets in strict foreign key dependency order
-- Expected Total Records: 500,526 rows across 8 tables
--
-- Execution (run from repository root):
--   psql -U <username> -d <database> -f postgreSQL/02_load_data.sql
-- =====================================================================

SET search_path TO public;

\echo '>>> [1/8] Loading departments (10 rows)...'
\copy departments(department_id, department_name, budget_egp, location) FROM 'dataset/departments.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [2/8] Loading roles (43 rows)...'
\copy roles(role_id, department_id, role_title, level, salary_band_min, salary_band_max) FROM 'dataset/roles.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [3/8] Loading employees (5,000 rows)...'
\copy employees(employee_id, first_name, last_name, email, department_id, role_id, salary, commission_pct, hire_date, termination_date, is_active, work_mode, manager_id) FROM 'dataset/employees.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [4/8] Loading employee_bank_accounts (5,000 rows)...'
\copy employee_bank_accounts(bank_account_id, employee_id, bank_name, iban, account_number) FROM 'dataset/employee_bank_accounts.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [5/8] Loading attendance (324,449 rows)...'
\copy attendance(attendance_id, employee_id, work_date, status, hours_worked, work_mode) FROM 'dataset/attendance.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [6/8] Loading role_permissions (125 rows)...'
\copy role_permissions(permission_id, role_id, permission_name, access_level, is_allowed) FROM 'dataset/role_permissions.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [7/8] Loading commissions (7,304 rows)...'
\copy commissions(commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount) FROM 'dataset/commissions.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> [8/8] Loading employee_kpis (158,595 rows)...'
\copy employee_kpis(kpi_id, employee_id, period_month, kpi_name, target, actual, score) FROM 'dataset/employee_kpis.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

-- ---------------------------------------------------------------------
-- Synchronize SERIAL / BIGSERIAL sequences to max IDs
-- Prevents key collision on subsequent manual INSERT operations
-- ---------------------------------------------------------------------
SELECT setval('departments_department_id_seq', (SELECT COALESCE(MAX(department_id), 1) FROM departments));
SELECT setval('roles_role_id_seq', (SELECT COALESCE(MAX(role_id), 1) FROM roles));
SELECT setval('employees_employee_id_seq', (SELECT COALESCE(MAX(employee_id), 1) FROM employees));
SELECT setval('employee_bank_accounts_bank_account_id_seq', (SELECT COALESCE(MAX(bank_account_id), 1) FROM employee_bank_accounts));
SELECT setval('attendance_attendance_id_seq', (SELECT COALESCE(MAX(attendance_id), 1) FROM attendance));
SELECT setval('role_permissions_permission_id_seq', (SELECT COALESCE(MAX(permission_id), 1) FROM role_permissions));
SELECT setval('commissions_commission_id_seq', (SELECT COALESCE(MAX(commission_id), 1) FROM commissions));
SELECT setval('employee_kpis_kpi_id_seq', (SELECT COALESCE(MAX(kpi_id), 1) FROM employee_kpis));

-- ---------------------------------------------------------------------
-- Comprehensive Row Count Audit & Integrity Verification
-- ---------------------------------------------------------------------
SELECT 
    table_name,
    loaded_rows,
    expected_rows,
    CASE WHEN loaded_rows = expected_rows THEN 'PASS' ELSE 'FAIL' END AS status
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
