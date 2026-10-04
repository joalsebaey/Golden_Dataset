-- =====================================================================
-- 02_load_data.sql - MySQL Data Ingestion & Integrity Audit
-- Loads all 8 canonical CSV datasets in strict foreign key order
-- Expected Total Records: 500,526 rows across 8 tables
--
-- Execution:
--   mysql -u <user> -p --local-infile=1 <database> < MySQL/02_load_data.sql
--   Or run within MySQL Workbench with "local_infile" enabled.
-- =====================================================================

SET GLOBAL local_infile = 1;

-- Temporarily disable foreign key checks and unique checks for fast bulk loading
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';

-- ---------------------------------------------------------------------
-- 1) departments (10 rows)
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
-- 2) roles (43 rows)
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
-- Empty strings in nullable fields (@salary, @termination_date, @manager_id) are mapped to NULL
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
-- Non-present records have empty hours and work_mode mapped to NULL
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
-- 6) role_permissions (125 rows)
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
-- 8) employee_kpis (158,595 rows)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'dataset/employee_kpis.csv'
INTO TABLE employee_kpis
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(kpi_id, employee_id, period_month, kpi_name, target, actual, score);

-- Re-enable constraints and validation checks
SET FOREIGN_KEY_CHECKS = 1;
SET UNIQUE_CHECKS = 1;

-- ---------------------------------------------------------------------
-- Comprehensive Row Count Audit & Integrity Verification
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
