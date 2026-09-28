-- =====================================================================
-- HR Schema (SQL Server / T-SQL) - Single tenant
-- Governed Schema aligned with schema.jpeg, dataset (*.csv), and Golden Evaluation Dataset
-- Compatible with SQL Server 2016+ (Unicode NVARCHAR, IDENTITY, Triggers)
-- =====================================================================

-- Clean teardown in reverse dependency order
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

-- ---------------------------------------------------------------------
-- 2) roles
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id          INT IDENTITY(1,1) PRIMARY KEY,
    department_id    INT NOT NULL CONSTRAINT fk_roles_department REFERENCES departments(department_id),
    role_title       NVARCHAR(100) NOT NULL,
    level            SMALLINT NOT NULL CONSTRAINT chk_roles_level CHECK (level BETWEEN 1 AND 10),
    salary_band_min  DECIMAL(12,2) NOT NULL,
    salary_band_max  DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_roles_salary_band CHECK (salary_band_max >= salary_band_min)
);

CREATE NONCLUSTERED INDEX idx_roles_department ON roles(department_id);

-- ---------------------------------------------------------------------
-- 3) employees
--    first_name / last_name contain Arabic or English (NVARCHAR)
--    commission_pct: 5.00 for Sales employees, 0 for everyone else
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id       INT IDENTITY(1,1) PRIMARY KEY,
    first_name        NVARCHAR(100) NOT NULL,
    last_name         NVARCHAR(100) NOT NULL,
    email             NVARCHAR(255) NOT NULL CONSTRAINT uq_employees_email UNIQUE,
    department_id     INT NOT NULL CONSTRAINT fk_emp_department REFERENCES departments(department_id),
    role_id           INT NOT NULL CONSTRAINT fk_emp_role REFERENCES roles(role_id),
    salary            DECIMAL(12,2) NULL CONSTRAINT chk_emp_salary CHECK (salary IS NULL OR salary >= 0),
    commission_pct    DECIMAL(5,2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_emp_commission_pct CHECK (commission_pct BETWEEN 0 AND 100),
    hire_date         DATE NOT NULL,
    termination_date  DATE NULL,
    is_active         BIT NOT NULL DEFAULT 1,
    work_mode         NVARCHAR(10) NOT NULL CONSTRAINT chk_emp_work_mode CHECK (work_mode IN ('onsite', 'remote', 'hybrid')),
    manager_id        INT NULL CONSTRAINT fk_emp_manager REFERENCES employees(employee_id),
    CONSTRAINT chk_emp_termination CHECK (termination_date IS NULL OR termination_date >= hire_date),
    CONSTRAINT chk_emp_manager CHECK (manager_id IS NULL OR manager_id <> employee_id)
);

CREATE NONCLUSTERED INDEX idx_employees_department ON employees(department_id);
CREATE NONCLUSTERED INDEX idx_employees_role       ON employees(role_id);
CREATE NONCLUSTERED INDEX idx_employees_manager    ON employees(manager_id);
CREATE NONCLUSTERED INDEX idx_employees_active     ON employees(is_active);

-- Guard: commission_pct > 0 is only allowed for the Sales department
GO
CREATE OR ALTER TRIGGER trg_employees_commission_sales_only
ON employees
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        LEFT JOIN departments d ON i.department_id = d.department_id
        WHERE i.commission_pct > 0
          AND (d.department_name IS NULL OR d.department_name <> 'Sales')
    )
    BEGIN
        RAISERROR ('commission_pct > 0 is allowed only for Sales employees', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts (1-to-1 relationship with employees)
-- ---------------------------------------------------------------------
CREATE TABLE employee_bank_accounts (
    bank_account_id  INT IDENTITY(1,1) PRIMARY KEY,
    employee_id      INT NOT NULL,
    bank_name        NVARCHAR(100) NOT NULL,
    iban             NVARCHAR(34) NOT NULL CONSTRAINT uq_bank_iban UNIQUE,
    account_number   NVARCHAR(30) NOT NULL,
    CONSTRAINT uq_bank_employee UNIQUE (employee_id),
    CONSTRAINT fk_bank_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
);



-- ---------------------------------------------------------------------
-- 5) attendance
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id     INT NOT NULL CONSTRAINT fk_att_employee REFERENCES employees(employee_id) ON DELETE CASCADE,
    work_date       DATE NOT NULL,
    status          NVARCHAR(15) NOT NULL,  -- e.g. present / absent / leave
    hours_worked    DECIMAL(4,2) NULL CONSTRAINT chk_att_hours CHECK (hours_worked IS NULL OR (hours_worked BETWEEN 0 AND 24)),
    work_mode       NVARCHAR(10) NULL CONSTRAINT chk_att_work_mode CHECK (work_mode IS NULL OR work_mode IN ('onsite', 'remote', 'hybrid')),
    CONSTRAINT uq_att_employee_date UNIQUE (employee_id, work_date),
    CONSTRAINT chk_att_status_consistency CHECK (
        (status = 'present' AND hours_worked IS NOT NULL AND work_mode IS NOT NULL) OR
        (status <> 'present' AND hours_worked IS NULL AND work_mode IS NULL)
    )
);

CREATE NONCLUSTERED INDEX idx_attendance_date ON attendance(work_date);

-- ---------------------------------------------------------------------
-- 6) role_permissions
-- ---------------------------------------------------------------------
CREATE TABLE role_permissions (
    permission_id    INT IDENTITY(1,1) PRIMARY KEY,
    role_id          INT NOT NULL CONSTRAINT fk_role_permissions_role REFERENCES roles(role_id) ON DELETE CASCADE,
    permission_name  NVARCHAR(100) NOT NULL,
    access_level     NVARCHAR(20) NOT NULL,  -- e.g. read / write / admin
    is_allowed       BIT NOT NULL DEFAULT 0,
    CONSTRAINT uq_role_permission UNIQUE (role_id, permission_name)
);

-- ---------------------------------------------------------------------
-- 7) commissions - actual monthly commission for Sales employees
-- ---------------------------------------------------------------------
CREATE TABLE commissions (
    commission_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id        INT NOT NULL CONSTRAINT fk_comm_employee REFERENCES employees(employee_id) ON DELETE CASCADE,
    period_month       DATE NOT NULL,
    sales_amount_egp   DECIMAL(14,2) NOT NULL CONSTRAINT chk_comm_sales CHECK (sales_amount_egp >= 0),
    commission_pct     DECIMAL(5,2) NOT NULL DEFAULT 5.00 CONSTRAINT chk_comm_pct CHECK (commission_pct BETWEEN 0 AND 100),
    commission_amount  DECIMAL(14,2) NOT NULL,
    CONSTRAINT uq_comm_employee_period UNIQUE (employee_id, period_month),
    CONSTRAINT chk_comm_period_day CHECK (DATEPART(day, period_month) = 1),
    CONSTRAINT chk_comm_amount_calc CHECK (commission_amount = ROUND(sales_amount_egp * commission_pct / 100.0, 2))
);

CREATE NONCLUSTERED INDEX idx_commissions_period ON commissions(period_month);

-- ---------------------------------------------------------------------
-- 8) employee_kpis - flexible monthly KPIs for all departments
-- ---------------------------------------------------------------------
CREATE TABLE employee_kpis (
    kpi_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id   INT NOT NULL CONSTRAINT fk_kpi_employee REFERENCES employees(employee_id) ON DELETE CASCADE,
    period_month  DATE NOT NULL,
    kpi_name      NVARCHAR(100) NOT NULL,
    target        DECIMAL(14,2) NOT NULL,
    actual        DECIMAL(14,2) NOT NULL,
    score         DECIMAL(5,2) NOT NULL CONSTRAINT chk_kpi_score CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT uq_kpi_employee_period_name UNIQUE (employee_id, period_month, kpi_name),
    CONSTRAINT chk_kpi_period_day CHECK (DATEPART(day, period_month) = 1)
);

CREATE NONCLUSTERED INDEX idx_kpis_period ON employee_kpis(period_month);
CREATE NONCLUSTERED INDEX idx_kpis_name   ON employee_kpis(kpi_name);