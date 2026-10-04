-- =====================================================================
-- 01_ddl.sql - PostgreSQL DDL (Data Definition Language)
-- Enterprise HR Canonical Schema (Phase 1 Benchmark)
-- Compatible with PostgreSQL 13+ (Public Schema)
--
-- IMPORT-FRIENDLY DESIGN:
--   This script creates all 8 tables with PRIMARY KEY, UNIQUE, CHECK
--   constraints and indexes - but WITHOUT foreign keys and WITHOUT the
--   Sales-commission trigger.
--
--   Why? employees.manager_id references employees itself, and the trigger
--   looks up departments. With FKs/trigger present, CSV imports fail with
--   error 23503 unless rows arrive in a perfect order.
--
--   Workflow:
--     1) Run 01_ddl.sql            -> empty tables, no FKs
--     2) Import the 8 CSV files    -> ANY order (DBeaver wizard or psql \copy)
--     3) Run 02_load_data.sql      -> orphan check, sequence sync,
--                                     ADD ALL FOREIGN KEYS + trigger, audit
--
--   WARNING: Re-running this script DROPS all tables and their data.
-- =====================================================================

SET search_path TO public;

-- Clean teardown (CASCADE also removes dependent views / FKs / triggers)
DROP TABLE IF EXISTS employee_kpis CASCADE;
DROP TABLE IF EXISTS commissions CASCADE;
DROP TABLE IF EXISTS role_permissions CASCADE;
DROP TABLE IF EXISTS attendance CASCADE;
DROP TABLE IF EXISTS employee_bank_accounts CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS roles CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP FUNCTION IF EXISTS trg_commission_sales_only() CASCADE;
DROP FUNCTION IF EXISTS trg_attendance_normalize_nulls() CASCADE;

-- ---------------------------------------------------------------------
-- 1) departments
-- Operational organizational units with allocated budgets
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id    SERIAL PRIMARY KEY,
    department_name  VARCHAR(100)  NOT NULL UNIQUE,
    budget_egp       NUMERIC(14,2) NOT NULL CHECK (budget_egp >= 0),
    location         VARCHAR(100)
);

-- ---------------------------------------------------------------------
-- 2) roles
-- Job positions mapped to departments with seniority levels and salary bands
-- FK (added in 02_load_data.sql): department_id -> departments
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id          SERIAL PRIMARY KEY,
    department_id    INT           NOT NULL,
    role_title       VARCHAR(100)  NOT NULL,
    level            SMALLINT      NOT NULL CHECK (level BETWEEN 1 AND 10),
    salary_band_min  NUMERIC(12,2) NOT NULL,
    salary_band_max  NUMERIC(12,2) NOT NULL,
    CHECK (salary_band_max >= salary_band_min)
);

CREATE INDEX idx_roles_department ON roles(department_id);

-- ---------------------------------------------------------------------
-- 3) employees
-- Core personnel with Arabic/English names (UTF-8), hierarchy, and work mode
-- FKs (added in 02_load_data.sql):
--   department_id -> departments, role_id -> roles,
--   manager_id    -> employees (self-reference)
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id       SERIAL PRIMARY KEY,
    first_name        VARCHAR(100)  NOT NULL,
    last_name         VARCHAR(100)  NOT NULL,
    email             VARCHAR(255)  NOT NULL UNIQUE,
    department_id     INT           NOT NULL,
    role_id           INT           NOT NULL,
    salary            NUMERIC(12,2) CHECK (salary IS NULL OR salary >= 0),   -- NULL allowed for null-handling testing
    commission_pct    NUMERIC(5,2)  NOT NULL DEFAULT 0.00 CHECK (commission_pct BETWEEN 0 AND 100),
    hire_date         DATE          NOT NULL,
    termination_date  DATE,
    is_active         SMALLINT      NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    work_mode         VARCHAR(10)   NOT NULL CHECK (work_mode IN ('onsite', 'remote', 'hybrid')),
    manager_id        INT,
    CHECK (termination_date IS NULL OR termination_date >= hire_date),
    CHECK (manager_id IS NULL OR manager_id <> employee_id)
);

CREATE INDEX idx_employees_department ON employees(department_id);
CREATE INDEX idx_employees_role       ON employees(role_id);
CREATE INDEX idx_employees_manager    ON employees(manager_id);
CREATE INDEX idx_employees_active     ON employees(is_active);

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts
-- Strictly 1-to-1 relationship with employees (UNIQUE employee_id)
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE employee_bank_accounts (
    bank_account_id  SERIAL PRIMARY KEY,
    employee_id      INT          NOT NULL UNIQUE,
    bank_name        VARCHAR(100) NOT NULL,
    iban             VARCHAR(34)  NOT NULL UNIQUE,
    account_number   VARCHAR(30)  NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 5) attendance
-- Daily attendance records enforcing strict presence/hours consistency
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id  BIGSERIAL PRIMARY KEY,
    employee_id    INT          NOT NULL,
    work_date      DATE         NOT NULL,
    status         VARCHAR(15)  NOT NULL,   -- 'present', 'absent', 'leave'
    hours_worked   NUMERIC(4,2) CHECK (hours_worked IS NULL OR (hours_worked BETWEEN 0 AND 24)),
    work_mode      VARCHAR(10)  CHECK (work_mode IS NULL OR work_mode IN ('onsite', 'remote', 'hybrid')),
    UNIQUE (employee_id, work_date),
    CONSTRAINT chk_att_status_consistency CHECK (
        (status = 'present' AND hours_worked IS NOT NULL AND work_mode IS NOT NULL) OR
        (status <> 'present' AND hours_worked IS NULL AND work_mode IS NULL)
    )
);

-- Auto-convert empty string '' to NULL on attendance.work_mode so GUI CSV importers
-- (like DBeaver Data Transfer with default settings) never fail on leave/absent rows.
CREATE OR REPLACE FUNCTION trg_attendance_normalize_nulls() RETURNS trigger AS $$
BEGIN
    NEW.work_mode := NULLIF(BTRIM(NEW.work_mode), '');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS attendance_normalize_nulls ON attendance;
CREATE TRIGGER attendance_normalize_nulls
    BEFORE INSERT OR UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION trg_attendance_normalize_nulls();

CREATE INDEX idx_attendance_date ON attendance(work_date);
-- NOTE: (employee_id, work_date) lookups are served by the UNIQUE constraint index above.

-- ---------------------------------------------------------------------
-- 6) role_permissions
-- RBAC permissions per role with defined access levels
-- FK (added in 02_load_data.sql): role_id -> roles ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE role_permissions (
    permission_id    SERIAL PRIMARY KEY,
    role_id          INT          NOT NULL,
    permission_name  VARCHAR(100) NOT NULL,
    access_level     VARCHAR(20)  NOT NULL CHECK (access_level IN ('read', 'write', 'admin')),
    is_allowed       SMALLINT     NOT NULL DEFAULT 0 CHECK (is_allowed IN (0, 1)),
    UNIQUE (role_id, permission_name)
);

-- ---------------------------------------------------------------------
-- 7) commissions
-- Monthly sales commissions for Sales reps; period_month always day 1
-- Enforces exact mathematical rounding: sales_amount_egp * commission_pct / 100
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE commissions (
    commission_id      BIGSERIAL PRIMARY KEY,
    employee_id        INT           NOT NULL,
    period_month       DATE          NOT NULL CHECK (EXTRACT(DAY FROM period_month) = 1),
    sales_amount_egp   NUMERIC(14,2) NOT NULL CHECK (sales_amount_egp >= 0),
    commission_pct     NUMERIC(5,2)  NOT NULL DEFAULT 5.00 CHECK (commission_pct BETWEEN 0 AND 100),
    commission_amount  NUMERIC(14,2) NOT NULL,
    UNIQUE (employee_id, period_month),
    CHECK (commission_amount = ROUND(sales_amount_egp * commission_pct / 100, 2))
);

CREATE INDEX idx_commissions_period ON commissions(period_month);

-- ---------------------------------------------------------------------
-- 8) employee_kpis
-- Monthly KPI targets, actual achievements, and bounded scores (0-100)
-- FK (added in 02_load_data.sql): employee_id -> employees ON DELETE CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE employee_kpis (
    kpi_id        BIGSERIAL PRIMARY KEY,
    employee_id   INT           NOT NULL,
    period_month  DATE          NOT NULL CHECK (EXTRACT(DAY FROM period_month) = 1),
    kpi_name      VARCHAR(100)  NOT NULL,
    target        NUMERIC(14,2) NOT NULL,
    actual        NUMERIC(14,2) NOT NULL,
    score         NUMERIC(5,2)  NOT NULL CHECK (score BETWEEN 0 AND 100),
    UNIQUE (employee_id, period_month, kpi_name)
);

CREATE INDEX idx_kpis_period ON employee_kpis(period_month);
CREATE INDEX idx_kpis_name   ON employee_kpis(kpi_name);

-- Tables are ready. Now import the 8 CSV files in ANY order,
-- then run 02_load_data.sql to add all foreign keys.
