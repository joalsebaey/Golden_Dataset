-- =====================================================================
-- 03_basic_select.sql - PostgreSQL Basic SELECT & Engine Smoke Test
-- Verifies connectivity, catalog registration, sample data retrieval,
-- and fundamental aggregations across all 8 canonical tables.
-- =====================================================================

SET search_path TO public;

-- ---------------------------------------------------------------------
-- 1. System Catalog Inspection: Live tuple count and table status
-- ---------------------------------------------------------------------
SELECT 
    schemaname,
    relname AS table_name,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples
FROM pg_stat_user_tables
ORDER BY relname;

-- ---------------------------------------------------------------------
-- 2. Sample Data Retrieval (LIMIT 3 from each table)
-- ---------------------------------------------------------------------
-- Departments
SELECT department_id, department_name, budget_egp, location 
FROM departments 
ORDER BY department_id 
LIMIT 3;

-- Roles
SELECT role_id, department_id, role_title, level, salary_band_min, salary_band_max 
FROM roles 
ORDER BY role_id 
LIMIT 3;

-- Employees
SELECT employee_id, first_name, last_name, email, department_id, salary, hire_date, is_active, work_mode 
FROM employees 
ORDER BY employee_id 
LIMIT 3;

-- Bank Accounts
SELECT bank_account_id, employee_id, bank_name, iban, account_number 
FROM employee_bank_accounts 
ORDER BY bank_account_id 
LIMIT 3;

-- Attendance
SELECT attendance_id, employee_id, work_date, status, hours_worked, work_mode 
FROM attendance 
ORDER BY work_date DESC, employee_id ASC 
LIMIT 3;

-- Role Permissions
SELECT permission_id, role_id, permission_name, access_level, is_allowed 
FROM role_permissions 
ORDER BY permission_id 
LIMIT 3;

-- Commissions
SELECT commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount 
FROM commissions 
ORDER BY period_month DESC, employee_id ASC 
LIMIT 3;

-- Employee KPIs
SELECT kpi_id, employee_id, period_month, kpi_name, target, actual, score 
FROM employee_kpis 
ORDER BY period_month DESC, employee_id ASC 
LIMIT 3;

-- ---------------------------------------------------------------------
-- 3. Executive Enterprise Summary Metrics
-- ---------------------------------------------------------------------
SELECT 
    (SELECT COUNT(*) FROM departments)                                      AS total_departments,
    (SELECT COUNT(*) FROM roles)                                            AS total_roles,
    (SELECT COUNT(*) FROM employees WHERE is_active = 1)                   AS active_employees,
    (SELECT COUNT(*) FROM employees WHERE is_active = 0)                   AS terminated_employees,
    (SELECT COUNT(*) FROM employees WHERE salary IS NULL)                  AS null_salary_fixtures,
    (SELECT ROUND(AVG(salary), 2) FROM employees WHERE is_active = 1)       AS avg_active_salary,
    (SELECT SUM(budget_egp) FROM departments)                               AS total_operational_budget_egp,
    (SELECT COUNT(*) FROM attendance)                                       AS total_attendance_logs,
    (SELECT MIN(work_date) FROM attendance)                                 AS earliest_attendance_date,
    (SELECT MAX(work_date) FROM attendance)                                 AS latest_attendance_date,
    (SELECT COUNT(*) FROM commissions)                                      AS total_commission_records,
    (SELECT ROUND(SUM(commission_amount), 2) FROM commissions)              AS total_commissions_paid_egp,
    (SELECT COUNT(*) FROM employee_kpis)                                    AS total_kpi_evaluations;
