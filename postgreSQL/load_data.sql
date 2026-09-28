-- =====================================================================
-- PostgreSQL Dataset Ingestion Script
-- Loads 8 governed CSV datasets into tenant_1 schema in correct FK order
-- Expected Total Rows: ~500,526 rows across 8 tables
-- =====================================================================

SET search_path TO tenant_1;

-- ---------------------------------------------------------------------
-- Option A: Running via psql command-line client (\copy)
-- Execute from the repository root directory:
--   psql -U <username> -d <database> -f postgreSQL/load_data.sql
-- ---------------------------------------------------------------------

\echo '>>> 1/8 Loading departments...'
\copy tenant_1.departments(department_id, department_name, budget_egp, location) FROM 'dataset/departments.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 2/8 Loading roles...'
\copy tenant_1.roles(role_id, department_id, role_title, level, salary_band_min, salary_band_max) FROM 'dataset/roles.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 3/8 Loading employees (5,000 rows)...'
\copy tenant_1.employees(employee_id, first_name, last_name, email, department_id, role_id, salary, commission_pct, hire_date, termination_date, is_active, work_mode, manager_id) FROM 'dataset/employees.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 4/8 Loading employee_bank_accounts (5,000 rows)...'
\copy tenant_1.employee_bank_accounts(bank_account_id, employee_id, bank_name, iban, account_number) FROM 'dataset/employee_bank_accounts.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 5/8 Loading attendance (324,449 rows)...'
\copy tenant_1.attendance(attendance_id, employee_id, work_date, status, hours_worked, work_mode) FROM 'dataset/attendance.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 6/8 Loading role_permissions (83 rows)...'
\copy tenant_1.role_permissions(permission_id, role_id, permission_name, access_level, is_allowed) FROM 'dataset/role_permissions.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 7/8 Loading commissions (7,304 rows)...'
\copy tenant_1.commissions(commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount) FROM 'dataset/commissions.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo '>>> 8/8 Loading employee_kpis (141,310 rows)...'
\copy tenant_1.employee_kpis(kpi_id, employee_id, period_month, kpi_name, target, actual, score) FROM 'dataset/employee_kpis.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

-- ---------------------------------------------------------------------
-- Synchronize SERIAL / BIGSERIAL sequences to max IDs
-- Essential so subsequent INSERTs do not collide with loaded keys!
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
-- Verification & Row Count Audit
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
