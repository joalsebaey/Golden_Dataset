-- =====================================================================
-- MySQL Dataset Ingestion Script
-- Loads 8 governed CSV datasets into the active database
-- Expected Total Rows: ~500,526 rows across 8 tables
--
-- Prerequisites:
--   Ensure local_infile is enabled:
--     mysql -u <user> -p --local-infile=1 <database> < MySQL/load_data.sql
--   Or execute within MySQL Workbench / client with Local Infile enabled.
-- =====================================================================

-- Temporarily disable foreign key checks and unique checks for fast bulk loading
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';

-- ---------------------------------------------------------------------
-- 1) departments
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/departments.csv'
INTO TABLE departments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(department_id, department_name, budget_egp, @location)
SET location = NULLIF(TRIM(@location), '');

-- ---------------------------------------------------------------------
-- 2) roles
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/roles.csv'
INTO TABLE roles
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(role_id, department_id, role_title, level, salary_band_min, salary_band_max);

-- ---------------------------------------------------------------------
-- 3) employees (5,000 rows)
--    Uses @variables for nullable columns to correctly map empty strings to NULL
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/employees.csv'
INTO TABLE employees
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(employee_id, first_name, last_name, email, department_id, role_id, @salary, commission_pct, hire_date, @termination_date, is_active, work_mode, @manager_id)
SET 
    salary = NULLIF(TRIM(@salary), ''),
    termination_date = NULLIF(TRIM(@termination_date), ''),
    manager_id = NULLIF(TRIM(@manager_id), '');

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts (5,000 rows)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/employee_bank_accounts.csv'
INTO TABLE employee_bank_accounts
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(bank_account_id, employee_id, bank_name, iban, account_number);

-- ---------------------------------------------------------------------
-- 5) attendance (324,449 rows)
--    Uses @variables for nullable hours_worked & work_mode (present vs absent/leave)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/attendance.csv'
INTO TABLE attendance
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(attendance_id, employee_id, work_date, status, @hours_worked, @work_mode)
SET 
    hours_worked = NULLIF(TRIM(@hours_worked), ''),
    work_mode = NULLIF(TRIM(@work_mode), '');

-- ---------------------------------------------------------------------
-- 6) role_permissions (83 rows)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/role_permissions.csv'
INTO TABLE role_permissions
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(permission_id, role_id, permission_name, access_level, is_allowed);

-- ---------------------------------------------------------------------
-- 7) commissions (7,304 rows)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/commissions.csv'
INTO TABLE commissions
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount);

-- ---------------------------------------------------------------------
-- 8) employee_kpis (141,310 rows)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/employee_kpis.csv'
INTO TABLE employee_kpis
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(kpi_id, employee_id, period_month, kpi_name, target, actual, score);

-- Re-enable foreign key checks and unique checks
SET FOREIGN_KEY_CHECKS = 1;
SET UNIQUE_CHECKS = 1;

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
