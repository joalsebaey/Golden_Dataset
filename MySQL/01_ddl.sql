-- =====================================================================
-- 01_ddl.sql - MySQL DDL (Data Definition Language)
-- Enterprise HR Canonical Schema (Phase 1 Benchmark)
-- Compatible with MySQL 8.0+ (InnoDB, UTF8MB4)
--
-- IMPORT-FRIENDLY DESIGN:
--   Creates all 8 tables with PRIMARY KEY, UNIQUE, CHECK constraints,
--   and indexes - WITHOUT foreign keys and WITHOUT triggers.
--   This allows you to import all 8 CSV files in ANY order (via DBeaver
--   Data Transfer wizard, MySQL Workbench, or LOAD DATA LOCAL INFILE)
--   without foreign key or self-referencing manager_id errors.
--   Then run 02_load_data.sql to add all 9 foreign keys and triggers.
-- =====================================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS employee_kpis;
DROP TABLE IF EXISTS commissions;
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS attendance;
DROP TABLE IF EXISTS employee_bank_accounts;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS departments;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1) departments
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id    INT AUTO_INCREMENT PRIMARY KEY,
    department_name  VARCHAR(100) NOT NULL UNIQUE,
    budget_egp       DECIMAL(14,2) NOT NULL,
    location         VARCHAR(100) NULL,
    CONSTRAINT chk_dept_budget CHECK (budget_egp >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 2) roles
-- FK (added in 02_load_data.sql): department_id -> departments
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id          INT AUTO_INCREMENT PRIMARY KEY,
    department_id    INT NOT NULL,
    role_title       VARCHAR(100) NOT NULL,
    level            SMALLINT NOT NULL,
    salary_band_min  DECIMAL(12,2) NOT NULL,
    salary_band_max  DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_roles_level CHECK (level BETWEEN 1 AND 10),
    CONSTRAINT chk_roles_salary_band CHECK (salary_band_max >= salary_band_min)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_roles_department ON roles(department_id);

-- ---------------------------------------------------------------------
-- 3) employees
-- FKs (added in 02_load_data.sql):
--   department_id -> departments, role_id -> roles, manager_id -> employees
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id       INT AUTO_INCREMENT PRIMARY KEY,
    first_name        VARCHAR(100) NOT NULL,
    last_name         VARCHAR(100) NOT NULL,
    email             VARCHAR(255) NOT NULL UNIQUE,
    department_id     INT NOT NULL,
    role_id           INT NOT NULL,
    salary            DECIMAL(12,2) NULL,   -- NULL allowed for null-handling testing
    commission_pct    DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    hire_date         DATE NOT NULL,
    termination_date  DATE NULL,
    is_active         TINYINT(1) NOT NULL DEFAULT 1,
    work_mode         VARCHAR(10) NOT NULL,
    manager_id        INT NULL,
    CONSTRAINT chk_emp_salary CHECK (salary IS NULL OR salary >= 0),
    CONSTRAINT chk_emp_commission_pct CHECK (commission_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_emp_work_mode CHECK (work_mode IN ('onsite', 'remote', 'hybrid')),
    CONSTRAINT chk_emp_termination CHECK (termination_date IS NULL OR termination_date >= hire_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_employees_department ON employees(department_id);
CREATE INDEX idx_employees_role       ON employees(role_id);
CREATE INDEX idx_employees_manager    ON employees(manager_id);
CREATE INDEX idx_employees_active     ON employees(is_active);

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts (1-to-1 with employees)
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE employee_bank_accounts (
    bank_account_id  INT AUTO_INCREMENT PRIMARY KEY,
    employee_id      INT NOT NULL UNIQUE,
    bank_name        VARCHAR(100) NOT NULL,
    iban             VARCHAR(34) NOT NULL UNIQUE,
    account_number   VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 5) attendance
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id  BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id    INT NOT NULL,
    work_date      DATE NOT NULL,
    status         VARCHAR(15) NOT NULL,
    hours_worked   DECIMAL(4,2) NULL,
    work_mode      VARCHAR(10) NULL,
    CONSTRAINT uq_att_emp_date UNIQUE (employee_id, work_date),
    CONSTRAINT chk_att_hours CHECK (hours_worked IS NULL OR (hours_worked BETWEEN 0 AND 24)),
    CONSTRAINT chk_att_mode CHECK (work_mode IS NULL OR work_mode IN ('onsite', 'remote', 'hybrid')),
    CONSTRAINT chk_att_status_consistency CHECK (
        (status = 'present' AND hours_worked IS NOT NULL AND work_mode IS NOT NULL) OR
        (status <> 'present' AND hours_worked IS NULL AND work_mode IS NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_attendance_date ON attendance(work_date);
CREATE INDEX idx_attendance_emp_date ON attendance(employee_id, work_date);

-- Auto-convert empty string '' to NULL on attendance.work_mode for GUI CSV importers
DELIMITER //
CREATE TRIGGER trg_attendance_before_insert
BEFORE INSERT ON attendance
FOR EACH ROW
BEGIN
    SET NEW.work_mode = NULLIF(TRIM(NEW.work_mode), '');
END//

CREATE TRIGGER trg_attendance_before_update
BEFORE UPDATE ON attendance
FOR EACH ROW
BEGIN
    SET NEW.work_mode = NULLIF(TRIM(NEW.work_mode), '');
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 6) role_permissions
-- FK (added in 02_load_data.sql): role_id -> roles ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE role_permissions (
    permission_id    INT AUTO_INCREMENT PRIMARY KEY,
    role_id          INT NOT NULL,
    permission_name  VARCHAR(100) NOT NULL,
    access_level     VARCHAR(20) NOT NULL,
    is_allowed       TINYINT(1) NOT NULL DEFAULT 0,
    CONSTRAINT uq_role_perm UNIQUE (role_id, permission_name),
    CONSTRAINT chk_perm_access CHECK (access_level IN ('read', 'write', 'admin'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_role_permissions_role ON role_permissions(role_id);

-- ---------------------------------------------------------------------
-- 7) commissions
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE commissions (
    commission_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id        INT NOT NULL,
    period_month       DATE NOT NULL,
    sales_amount_egp   DECIMAL(14,2) NOT NULL,
    commission_pct     DECIMAL(5,2) NOT NULL DEFAULT 5.00,
    commission_amount  DECIMAL(14,2) NOT NULL,
    CONSTRAINT uq_comm_emp_period UNIQUE (employee_id, period_month),
    CONSTRAINT chk_comm_period_day1 CHECK (DAY(period_month) = 1),
    CONSTRAINT chk_comm_sales CHECK (sales_amount_egp >= 0),
    CONSTRAINT chk_comm_pct CHECK (commission_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_comm_math CHECK (commission_amount = ROUND(sales_amount_egp * commission_pct / 100.0, 2))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_commissions_period ON commissions(period_month);
CREATE INDEX idx_commissions_employee ON commissions(employee_id);

-- ---------------------------------------------------------------------
-- 8) employee_kpis
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE employee_kpis (
    kpi_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id   INT NOT NULL,
    period_month  DATE NOT NULL,
    kpi_name      VARCHAR(100) NOT NULL,
    target        DECIMAL(14,2) NOT NULL,
    actual        DECIMAL(14,2) NOT NULL,
    score         DECIMAL(5,2) NOT NULL,
    CONSTRAINT uq_kpi_emp_period_name UNIQUE (employee_id, period_month, kpi_name),
    CONSTRAINT chk_kpi_period_day1 CHECK (DAY(period_month) = 1),
    CONSTRAINT chk_kpi_score CHECK (score BETWEEN 0 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_kpis_period ON employee_kpis(period_month);
CREATE INDEX idx_kpis_employee ON employee_kpis(employee_id);
CREATE INDEX idx_kpis_name ON employee_kpis(kpi_name);

-- Tables are ready. Import the 8 CSV files in ANY order,
-- then run 02_load_data.sql to add all foreign keys and triggers.
