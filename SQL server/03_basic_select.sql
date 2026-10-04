-- =====================================================================
-- 03_basic_select.sql - SQL Server Basic SELECT & Engine Smoke Test
-- Verifies connectivity, table catalog registration, sample data retrieval,
-- and fundamental aggregations across all 8 canonical tables.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. System Catalog Inspection: Table storage and row count estimations
-- ---------------------------------------------------------------------
SELECT 
    t.name AS table_name,
    p.rows AS estimated_row_count,
    CAST(ROUND((SUM(a.total_pages) * 8) / 1024.0, 2) AS NUMERIC(10, 2)) AS total_space_mb,
    CAST(ROUND((SUM(a.used_pages) * 8) / 1024.0, 2) AS NUMERIC(10, 2)) AS used_space_mb
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.is_ms_shipped = 0 AND i.index_id <= 1
GROUP BY t.name, p.rows
ORDER BY t.name;
GO

-- ---------------------------------------------------------------------
-- 2. Sample Data Retrieval (TOP 3 from each table)
-- ---------------------------------------------------------------------
-- Departments
SELECT TOP 3 department_id, department_name, budget_egp, location 
FROM departments 
ORDER BY department_id;

-- Roles
SELECT TOP 3 role_id, department_id, role_title, level, salary_band_min, salary_band_max 
FROM roles 
ORDER BY role_id;

-- Employees
SELECT TOP 3 employee_id, first_name, last_name, email, department_id, salary, hire_date, is_active, work_mode 
FROM employees 
ORDER BY employee_id;

-- Bank Accounts
SELECT TOP 3 bank_account_id, employee_id, bank_name, iban, account_number 
FROM employee_bank_accounts 
ORDER BY bank_account_id;

-- Attendance
SELECT TOP 3 attendance_id, employee_id, work_date, status, hours_worked, work_mode 
FROM attendance 
ORDER BY work_date DESC, employee_id ASC;

-- Role Permissions
SELECT TOP 3 permission_id, role_id, permission_name, access_level, is_allowed 
FROM role_permissions 
ORDER BY permission_id;

-- Commissions
SELECT TOP 3 commission_id, employee_id, period_month, sales_amount_egp, commission_pct, commission_amount 
FROM commissions 
ORDER BY period_month DESC, employee_id ASC;

-- Employee KPIs
SELECT TOP 3 kpi_id, employee_id, period_month, kpi_name, target, actual, score 
FROM employee_kpis 
ORDER BY period_month DESC, employee_id ASC;
GO

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
GO
