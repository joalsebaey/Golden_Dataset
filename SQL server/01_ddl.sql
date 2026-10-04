-- =====================================================================
-- 01_ddl.sql - SQL Server DDL (Data Definition Language)
-- Enterprise HR Canonical Schema (Phase 1 Benchmark)
-- Compatible with SQL Server 2016+ (T-SQL, Unicode NVARCHAR, IDENTITY)
--
-- IMPORT-FRIENDLY DESIGN:
--   Creates all 8 tables with PRIMARY KEY, UNIQUE, CHECK constraints,
--   and indexes - WITHOUT foreign keys and WITHOUT triggers.
--   This allows you to import all 8 CSV files in ANY order (via DBeaver
--   Data Transfer wizard, SSMS Import Wizard, or BULK INSERT) without
--   foreign key or self-referencing manager_id errors.
--   Then run 02_load_data.sql to add all 9 foreign keys and the trigger.
-- =====================================================================

-- Drop any existing foreign keys first so teardown never fails on order
DECLARE @drop_fks NVARCHAR(MAX) = N'';
SELECT @drop_fks += N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))
                 + N'.' + QUOTENAME(OBJECT_NAME(parent_object_id))
                 + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';' + CHAR(13)
FROM sys.foreign_keys
WHERE OBJECT_NAME(parent_object_id) IN (
    'departments','roles','employees','employee_bank_accounts',
    'attendance','role_permissions','commissions','employee_kpis'
);
IF @drop_fks <> N'' EXEC sp_executesql @drop_fks;
GO

IF OBJECT_ID('employee_kpis', 'U') IS NOT NULL DROP TABLE employee_kpis;
IF OBJECT_ID('commissions', 'U') IS NOT NULL DROP TABLE commissions;
IF OBJECT_ID('role_permissions', 'U') IS NOT NULL DROP TABLE role_permissions;
IF OBJECT_ID('attendance', 'U') IS NOT NULL DROP TABLE attendance;
IF OBJECT_ID('employee_bank_accounts', 'U') IS NOT NULL DROP TABLE employee_bank_accounts;
IF OBJECT_ID('employees', 'U') IS NOT NULL DROP TABLE employees;
IF OBJECT_ID('roles', 'U') IS NOT NULL DROP TABLE roles;
IF OBJECT_ID('departments', 'U') IS NOT NULL DROP TABLE departments;
GO

-- ---------------------------------------------------------------------
-- 1) departments
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id    INT IDENTITY(1,1) PRIMARY KEY,
    department_name  NVARCHAR(100) NOT NULL CONSTRAINT uq_departments_name UNIQUE,
    budget_egp       DECIMAL(14,2) NOT NULL CONSTRAINT chk_dept_budget CHECK (budget_egp >= 0),
    location         NVARCHAR(100) NULL
);
GO

-- ---------------------------------------------------------------------
-- 2) roles
-- FK (added in 02_load_data.sql): department_id -> departments
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id          INT IDENTITY(1,1) PRIMARY KEY,
    department_id    INT NOT NULL,
    role_title       NVARCHAR(100) NOT NULL,
    level            SMALLINT NOT NULL CONSTRAINT chk_roles_level CHECK (level BETWEEN 1 AND 10),
    salary_band_min  DECIMAL(12,2) NOT NULL,
    salary_band_max  DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_roles_salary_band CHECK (salary_band_max >= salary_band_min)
);
GO

CREATE NONCLUSTERED INDEX idx_roles_department ON roles(department_id);
GO

-- ---------------------------------------------------------------------
-- 3) employees
-- FKs (added in 02_load_data.sql):
--   department_id -> departments, role_id -> roles, manager_id -> employees
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id       INT IDENTITY(1,1) PRIMARY KEY,
    first_name        NVARCHAR(100) NOT NULL,
    last_name         NVARCHAR(100) NOT NULL,
    email             NVARCHAR(255) NOT NULL CONSTRAINT uq_employees_email UNIQUE,
    department_id     INT NOT NULL,
    role_id           INT NOT NULL,
    salary            DECIMAL(12,2) NULL CONSTRAINT chk_emp_salary CHECK (salary IS NULL OR salary >= 0),
    commission_pct    DECIMAL(5,2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_emp_commission_pct CHECK (commission_pct BETWEEN 0 AND 100),
    hire_date         DATE NOT NULL,
    termination_date  DATE NULL,
    is_active         BIT NOT NULL DEFAULT 1,
    work_mode         NVARCHAR(10) NOT NULL CONSTRAINT chk_emp_work_mode CHECK (work_mode IN ('onsite', 'remote', 'hybrid')),
    manager_id        INT NULL,
    CONSTRAINT chk_emp_termination CHECK (termination_date IS NULL OR termination_date >= hire_date),
    CONSTRAINT chk_emp_manager CHECK (manager_id IS NULL OR manager_id <> employee_id)
);
GO

CREATE NONCLUSTERED INDEX idx_employees_department ON employees(department_id);
CREATE NONCLUSTERED INDEX idx_employees_role       ON employees(role_id);
CREATE NONCLUSTERED INDEX idx_employees_manager    ON employees(manager_id);
CREATE NONCLUSTERED INDEX idx_employees_active     ON employees(is_active);
GO

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts (1-to-1 with employees)
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE employee_bank_accounts (
    bank_account_id  INT IDENTITY(1,1) PRIMARY KEY,
    employee_id      INT NOT NULL CONSTRAINT uq_bank_emp UNIQUE,
    bank_name        NVARCHAR(100) NOT NULL,
    iban             NVARCHAR(34) NOT NULL CONSTRAINT uq_bank_iban UNIQUE,
    account_number   NVARCHAR(30) NOT NULL CONSTRAINT uq_bank_acc UNIQUE
);
GO

-- ---------------------------------------------------------------------
-- 5) attendance
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id  BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id    INT NOT NULL,
    work_date      DATE NOT NULL,
    status         NVARCHAR(15) NOT NULL,
    hours_worked   DECIMAL(4,2) NULL,
    work_mode      NVARCHAR(10) NULL,
    CONSTRAINT uq_att_emp_date UNIQUE (employee_id, work_date),
    CONSTRAINT chk_att_hours CHECK (hours_worked IS NULL OR (hours_worked BETWEEN 0 AND 24))
    -- chk_att_mode and chk_att_status_consistency are added in 02_load_data.sql
    -- after normalizing any GUI-imported empty string '' on work_mode to NULL.
);
GO

CREATE NONCLUSTERED INDEX idx_attendance_date ON attendance(work_date);
CREATE NONCLUSTERED INDEX idx_attendance_emp_date ON attendance(employee_id, work_date);
GO

-- ---------------------------------------------------------------------
-- 6) role_permissions
-- FK (added in 02_load_data.sql): role_id -> roles ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE role_permissions (
    permission_id    INT IDENTITY(1,1) PRIMARY KEY,
    role_id          INT NOT NULL,
    permission_name  NVARCHAR(100) NOT NULL,
    access_level     NVARCHAR(20) NOT NULL CONSTRAINT chk_perm_access CHECK (access_level IN ('read', 'write', 'admin')),
    is_allowed       BIT NOT NULL DEFAULT 0,
    CONSTRAINT uq_role_perm UNIQUE (role_id, permission_name)
);
GO

CREATE NONCLUSTERED INDEX idx_role_permissions_role ON role_permissions(role_id);
GO

-- ---------------------------------------------------------------------
-- 7) commissions
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE commissions (
    commission_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id        INT NOT NULL,
    period_month       DATE NOT NULL,
    sales_amount_egp   DECIMAL(14,2) NOT NULL CONSTRAINT chk_comm_sales CHECK (sales_amount_egp >= 0),
    commission_pct     DECIMAL(5,2) NOT NULL DEFAULT 5.00 CONSTRAINT chk_comm_pct CHECK (commission_pct BETWEEN 0 AND 100),
    commission_amount  DECIMAL(14,2) NOT NULL,
    CONSTRAINT uq_comm_emp_period UNIQUE (employee_id, period_month),
    CONSTRAINT chk_comm_period_day1 CHECK (DATEPART(day, period_month) = 1),
    CONSTRAINT chk_comm_math CHECK (commission_amount = ROUND(sales_amount_egp * commission_pct / 100.0, 2))
);
GO

CREATE NONCLUSTERED INDEX idx_commissions_period ON commissions(period_month);
CREATE NONCLUSTERED INDEX idx_commissions_employee ON commissions(employee_id);
GO

-- ---------------------------------------------------------------------
-- 8) employee_kpis
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE employee_kpis (
    kpi_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id   INT NOT NULL,
    period_month  DATE NOT NULL,
    kpi_name      NVARCHAR(100) NOT NULL,
    target        DECIMAL(14,2) NOT NULL,
    actual        DECIMAL(14,2) NOT NULL,
    score         DECIMAL(5,2) NOT NULL CONSTRAINT chk_kpi_score CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT uq_kpi_emp_period_name UNIQUE (employee_id, period_month, kpi_name),
    CONSTRAINT chk_kpi_period_day1 CHECK (DATEPART(day, period_month) = 1)
);
GO

CREATE NONCLUSTERED INDEX idx_kpis_period ON employee_kpis(period_month);
CREATE NONCLUSTERED INDEX idx_kpis_employee ON employee_kpis(employee_id);
CREATE NONCLUSTERED INDEX idx_kpis_name ON employee_kpis(kpi_name);
GO

-- Tables are ready. Import the 8 CSV files in ANY order,
-- then run 02_load_data.sql to add all foreign keys and the trigger.
