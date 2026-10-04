-- =====================================================================
-- 02_load_data.sql - MySQL Data Import + Foreign Key & Trigger Finalization
-- Expected Total Records: 500,526 rows across 8 tables
--
-- PREREQUISITE: Run 01_ddl.sql first (creates tables WITHOUT foreign keys).
--
-- Two ways to load the CSVs:
--   Option A (GUI): Import all 8 CSVs in ANY order using DBeaver Data Transfer
--                   wizard (set "Empty strings to NULL" = checked, UTF-8),
--                   then run this script from STEP 2 onward.
--   Option B (CLI): Run this entire script with mysql --local-infile=1 from
--                   the repository root (uncomment STEP 1 below if needed).
-- =====================================================================

-- =====================================================================
-- STEP 1 (OPTIONAL - CLI): Bulk Load via LOAD DATA LOCAL INFILE
-- If you already imported the CSVs via DBeaver/Workbench, skip to STEP 2.
-- =====================================================================
/*
SET GLOBAL local_infile = 1;
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';

LOAD DATA LOCAL INFILE 'dataset/departments.csv' INTO TABLE departments CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(department_id, department_name, budget_egp, @location)
SET location = NULLIF(TRIM(BOTH '\r' FROM @location), '');

LOAD DATA LOCAL INFILE 'dataset/roles.csv' INTO TABLE roles CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(role_id, department_id, role_title, level, salary_band_min, salary_band_max);

LOAD DATA LOCAL INFILE 'dataset/employees.csv' INTO TABLE employees CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(employee_id, first_name, last_name, email, department_id, role_id, @salary, commission_pct, hire_date, @termination_date, is_active, work_mode, @manager_id)
SET salary = NULLIF(TRIM(BOTH '\r' FROM @salary), ''),
    termination_date = NULLIF(TRIM(BOTH '\r' FROM @termination_date), ''),
    manager_id = NULLIF(TRIM(BOTH '\r' FROM @manager_id), '');

LOAD DATA LOCAL INFILE 'dataset/employee_bank_accounts.csv' INTO TABLE employee_bank_accounts CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(bank_account_id, employee_id, bank_name, iban, account_number);

LOAD DATA LOCAL INFILE 'dataset/attendance.csv' INTO TABLE attendance CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(attendance_id, employee_id, work_date, status, @hours_worked, @work_mode)
SET hours_worked = NULLIF(TRIM(BOTH '\r' FROM @hours_worked), ''),
    work_mode = NULLIF(TRIM(BOTH '\r' FROM @work_mode), '');

LOAD DATA LOCAL INFILE 'dataset/role_permissions.csv' INTO TABLE role_permissions CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(permission_id, role_id, permission_name, access_level, is_allowed);

LOAD DATA LOCAL INFILE 'dataset/commissions.csv' INTO TABLE commissions CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount);

LOAD DATA LOCAL INFILE 'dataset/employee_kpis.csv' INTO TABLE employee_kpis CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\' LINES TERMINATED BY '\n' IGNORE 1 LINES
(kpi_id, employee_id, period_month, kpi_name, target, actual, score);

SET UNIQUE_CHECKS = 1;
SET FOREIGN_KEY_CHECKS = 1;
*/

-- =====================================================================
-- STEP 2: PRE-FLIGHT ORPHAN CHECK (Every orphan_rows value must be 0)
-- =====================================================================
SELECT relationship, orphan_rows,
       CASE WHEN orphan_rows = 0 THEN 'OK' ELSE 'FIX DATA BEFORE STEP 3' END AS status
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

-- =====================================================================
-- STEP 3: ADD ALL 9 FOREIGN KEYS (After data is loaded)
-- =====================================================================
ALTER TABLE roles
    ADD CONSTRAINT fk_roles_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id);

ALTER TABLE employees
    ADD CONSTRAINT fk_employees_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id),
    ADD CONSTRAINT fk_employees_role
    FOREIGN KEY (role_id) REFERENCES roles(role_id),
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

-- =====================================================================
-- STEP 4: ADD BUSINESS-RULE TRIGGERS (Sales-only commission & self-manager guard)
-- =====================================================================
DROP TRIGGER IF EXISTS trg_employees_before_insert;
DROP TRIGGER IF EXISTS trg_employees_before_update;

DELIMITER //

CREATE TRIGGER trg_employees_before_insert
BEFORE INSERT ON employees
FOR EACH ROW
BEGIN
    DECLARE v_dept_name VARCHAR(100);
    IF NEW.manager_id IS NOT NULL AND NEW.employee_id IS NOT NULL AND NEW.manager_id = NEW.employee_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'An employee cannot be their own manager (manager_id = employee_id)';
    END IF;
    IF NEW.commission_pct > 0 THEN
        SELECT department_name INTO v_dept_name FROM departments WHERE department_id = NEW.department_id;
        IF v_dept_name IS NULL OR v_dept_name <> 'Sales' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'commission_pct > 0 is allowed only for Sales department employees';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_employees_before_update
BEFORE UPDATE ON employees
FOR EACH ROW
BEGIN
    DECLARE v_dept_name VARCHAR(100);
    IF NEW.manager_id IS NOT NULL AND NEW.manager_id = NEW.employee_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'An employee cannot be their own manager (manager_id = employee_id)';
    END IF;
    IF NEW.commission_pct > 0 THEN
        SELECT department_name INTO v_dept_name FROM departments WHERE department_id = NEW.department_id;
        IF v_dept_name IS NULL OR v_dept_name <> 'Sales' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'commission_pct > 0 is allowed only for Sales department employees';
        END IF;
    END IF;
END//

DELIMITER ;

-- =====================================================================
-- STEP 5: VERIFICATION (Row Counts & Foreign Keys)
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

SELECT table_name AS child_table, constraint_name, referenced_table_name AS parent_table
FROM information_schema.key_column_usage
WHERE table_schema = DATABASE() AND referenced_table_name IS NOT NULL
ORDER BY 1, 2;
