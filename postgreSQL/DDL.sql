-- =====================================================================
-- HR Schema (PostgreSQL) - Default public schema
-- ~5,000 employees | ~500k rows estimated
-- Governed Schema aligned with schema.jpeg, dataset (*.csv), and Golden Evaluation Dataset
-- =====================================================================

SET search_path TO public;

-- Clean teardown in reverse dependency order
DROP TABLE IF EXISTS employee_kpis CASCADE;
DROP TABLE IF EXISTS commissions CASCADE;
DROP TABLE IF EXISTS role_permissions CASCADE;
DROP TABLE IF EXISTS attendance CASCADE;
DROP TABLE IF EXISTS employee_bank_accounts CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS roles CASCADE;
DROP TABLE IF EXISTS departments CASCADE;

-- ---------------------------------------------------------------------
-- 1) departments
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id    SERIAL PRIMARY KEY,
    department_name  VARCHAR(100)  NOT NULL UNIQUE,
    budget_egp       NUMERIC(14,2) NOT NULL CHECK (budget_egp >= 0),
    location         VARCHAR(100)
);

-- ---------------------------------------------------------------------
-- 2) roles
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id          SERIAL PRIMARY KEY,
    department_id    INT           NOT NULL REFERENCES departments(department_id),
    role_title       VARCHAR(100)  NOT NULL,
    level            SMALLINT      NOT NULL CHECK (level BETWEEN 1 AND 10),
    salary_band_min  NUMERIC(12,2) NOT NULL,
    salary_band_max  NUMERIC(12,2) NOT NULL,
    CHECK (salary_band_max >= salary_band_min)
);
CREATE INDEX idx_roles_department ON roles(department_id);

-- ---------------------------------------------------------------------
-- 3) employees
--    first_name / last_name contain Arabic or English (UTF-8)
--    commission_pct: 5.00 for Sales employees, 0 for everyone else
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id       SERIAL PRIMARY KEY,
    first_name        VARCHAR(100)  NOT NULL,
    last_name         VARCHAR(100)  NOT NULL,
    email             VARCHAR(255)  NOT NULL UNIQUE,
    department_id     INT           NOT NULL REFERENCES departments(department_id),
    role_id           INT           NOT NULL REFERENCES roles(role_id),
    salary            NUMERIC(12,2) CHECK (salary >= 0),   -- NULL allowed (NULL-handling fixture)
    commission_pct    NUMERIC(5,2)  NOT NULL DEFAULT 0
                      CHECK (commission_pct BETWEEN 0 AND 100),
    hire_date         DATE          NOT NULL,
    termination_date  DATE,
    is_active         SMALLINT      NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    work_mode         VARCHAR(10)   NOT NULL CHECK (work_mode IN ('onsite','remote','hybrid')),
    manager_id        INT           REFERENCES employees(employee_id),
    CHECK (termination_date IS NULL OR termination_date >= hire_date),
    CHECK (manager_id IS NULL OR manager_id <> employee_id)
);
CREATE INDEX idx_employees_department ON employees(department_id);
CREATE INDEX idx_employees_role       ON employees(role_id);
CREATE INDEX idx_employees_manager    ON employees(manager_id);
CREATE INDEX idx_employees_active     ON employees(is_active);

-- Guard: commission_pct > 0 is only allowed for the Sales department
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

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts (1-to-1 relationship with employees)
-- ---------------------------------------------------------------------
CREATE TABLE employee_bank_accounts (
    bank_account_id  SERIAL PRIMARY KEY,
    employee_id      INT          NOT NULL UNIQUE REFERENCES employees(employee_id) ON DELETE CASCADE,
    bank_name        VARCHAR(100) NOT NULL,
    iban             VARCHAR(34)  NOT NULL UNIQUE,
    account_number   VARCHAR(30)  NOT NULL
);


-- ---------------------------------------------------------------------
-- 5) attendance
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id  BIGSERIAL PRIMARY KEY,
    employee_id    INT          NOT NULL REFERENCES employees(employee_id) ON DELETE CASCADE,
    work_date      DATE         NOT NULL,
    status         VARCHAR(15)  NOT NULL,   -- e.g. present / absent / leave
    hours_worked   NUMERIC(4,2) CHECK (hours_worked BETWEEN 0 AND 24),   -- NULL unless present
    work_mode      VARCHAR(10)  CHECK (work_mode IN ('onsite','remote','hybrid')),  -- NULL unless present
    UNIQUE (employee_id, work_date),
    CONSTRAINT chk_att_status_consistency CHECK (
        (status = 'present' AND hours_worked IS NOT NULL AND work_mode IS NOT NULL) OR
        (status <> 'present' AND hours_worked IS NULL AND work_mode IS NULL)
    )
);
CREATE INDEX idx_attendance_date ON attendance(work_date);

-- ---------------------------------------------------------------------
-- 6) role_permissions
-- ---------------------------------------------------------------------
CREATE TABLE role_permissions (
    permission_id    SERIAL PRIMARY KEY,
    role_id          INT          NOT NULL REFERENCES roles(role_id) ON DELETE CASCADE,
    permission_name  VARCHAR(100) NOT NULL,
    access_level     VARCHAR(20)  NOT NULL,  -- e.g. read / write / admin
    is_allowed       SMALLINT     NOT NULL DEFAULT 0 CHECK (is_allowed IN (0, 1)),
    UNIQUE (role_id, permission_name)
);

-- ---------------------------------------------------------------------
-- 7) commissions - actual monthly commission for Sales employees
-- ---------------------------------------------------------------------
CREATE TABLE commissions (
    commission_id      BIGSERIAL PRIMARY KEY,
    employee_id        INT           NOT NULL REFERENCES employees(employee_id) ON DELETE CASCADE,
    period_month       DATE          NOT NULL CHECK (EXTRACT(DAY FROM period_month) = 1),
    sales_amount_egp   NUMERIC(14,2) NOT NULL CHECK (sales_amount_egp >= 0),
    commission_pct     NUMERIC(5,2)  NOT NULL DEFAULT 5.00 CHECK (commission_pct BETWEEN 0 AND 100),
    commission_amount  NUMERIC(14,2) NOT NULL,
    UNIQUE (employee_id, period_month),
    CHECK (commission_amount = ROUND(sales_amount_egp * commission_pct / 100, 2))
);
CREATE INDEX idx_commissions_period ON commissions(period_month);

-- ---------------------------------------------------------------------
-- 8) employee_kpis - flexible monthly KPIs for all departments
-- ---------------------------------------------------------------------
CREATE TABLE employee_kpis (
    kpi_id        BIGSERIAL PRIMARY KEY,
    employee_id   INT           NOT NULL REFERENCES employees(employee_id) ON DELETE CASCADE,
    period_month  DATE          NOT NULL CHECK (EXTRACT(DAY FROM period_month) = 1),
    kpi_name      VARCHAR(100)  NOT NULL,
    target        NUMERIC(14,2) NOT NULL,
    actual        NUMERIC(14,2) NOT NULL,
    score         NUMERIC(5,2)  NOT NULL CHECK (score BETWEEN 0 AND 100),
    UNIQUE (employee_id, period_month, kpi_name)
);
CREATE INDEX idx_kpis_period   ON employee_kpis(period_month);
CREATE INDEX idx_kpis_name     ON employee_kpis(kpi_name);
