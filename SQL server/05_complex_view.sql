-- =====================================================================
-- 05_complex_view.sql - SQL Server Complicated VIEW & Engine Optimizer Stress Test
-- Builds a comprehensive 8-table enterprise analytical VIEW integrating window functions,
-- string aggregations, pre-aggregated CTEs, and multi-metric employee scoring.
-- =====================================================================

IF OBJECT_ID('vw_enterprise_hr_360_analytics', 'V') IS NOT NULL 
    DROP VIEW vw_enterprise_hr_360_analytics;
GO

-- ---------------------------------------------------------------------
-- Create Complicated 360-Degree Analytical View
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW vw_enterprise_hr_360_analytics AS
WITH role_perms_agg AS (
    -- Subquery 1: Aggregated permissions per role
    SELECT 
        role_id,
        STRING_AGG(permission_name, ', ') WITHIN GROUP (ORDER BY permission_name) AS permissions_list,
        COUNT(DISTINCT permission_name) AS total_permissions_granted
    FROM role_permissions
    WHERE is_allowed = 1
    GROUP BY role_id
),
kpi_summary AS (
    -- Subquery 2: Multi-month KPI evaluation aggregations
    SELECT 
        employee_id,
        COUNT(DISTINCT period_month) AS total_evaluation_months,
        COUNT(*) AS total_kpi_metrics_evaluated,
        ROUND(AVG(score), 2) AS overall_avg_kpi_score,
        ROUND(MIN(score), 2) AS min_kpi_score,
        ROUND(MAX(score), 2) AS max_kpi_score,
        ROUND(SUM(actual) / NULLIF(SUM(target), 0) * 100.0, 2) AS target_achievement_pct
    FROM employee_kpis
    GROUP BY employee_id
),
commission_summary AS (
    -- Subquery 3: Cumulative sales and commission performance
    SELECT 
        employee_id,
        COUNT(DISTINCT period_month) AS active_sales_months,
        ROUND(SUM(sales_amount_egp), 2) AS total_sales_generated_egp,
        ROUND(SUM(commission_amount), 2) AS total_commission_earned_egp,
        ROUND(AVG(commission_pct), 2) AS avg_commission_rate_pct
    FROM commissions
    GROUP BY employee_id
),
attendance_metrics AS (
    -- Subquery 4: Aggregation over 324K+ attendance records
    SELECT 
        employee_id,
        COUNT(*) AS total_work_days_logged,
        SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS days_present,
        SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) AS days_absent,
        SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END) AS days_leave,
        ROUND(SUM(hours_worked), 2) AS total_hours_worked,
        ROUND(AVG(CASE WHEN status = 'present' THEN hours_worked END), 2) AS avg_hours_per_present_day,
        ROUND(SUM(CASE WHEN status = 'present' AND work_mode = 'remote' THEN 1 ELSE 0 END) * 100.0 / 
              NULLIF(SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END), 0), 2) AS remote_work_ratio_pct
    FROM attendance
    GROUP BY employee_id
)
SELECT 
    -- 1. Employee Core Dimensions
    e.employee_id,
    e.first_name + ' ' + e.last_name AS full_name,
    e.email,
    e.hire_date,
    e.termination_date,
    e.is_active,
    e.work_mode AS primary_work_mode,
    DATEDIFF(YEAR, e.hire_date, ISNULL(e.termination_date, GETDATE())) AS tenure_years,

    -- 2. Managerial Hierarchy
    e.manager_id,
    m.first_name + ' ' + m.last_name AS manager_name,

    -- 3. Department & Organizational Unit
    d.department_id,
    d.department_name,
    d.location AS department_location,
    d.budget_egp AS department_annual_budget_egp,

    -- 4. Role & Permissions
    r.role_id,
    r.role_title,
    r.level AS role_seniority_level,
    r.salary_band_min,
    r.salary_band_max,
    ISNULL(rp.permissions_list, 'None') AS assigned_permissions,
    ISNULL(rp.total_permissions_granted, 0) AS permissions_count,

    -- 5. Compensation & Window Analytics
    e.salary,
    ROUND(e.salary - AVG(e.salary) OVER (PARTITION BY e.department_id), 2) AS salary_diff_from_dept_avg,
    DENSE_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary DESC) AS dept_salary_rank,
    ROUND(PERCENT_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary ASC), 4) AS dept_salary_percentile,

    -- 6. Banking Detail (Masked IBAN for security)
    b.bank_name,
    LEFT(b.iban, 4) + '****' + RIGHT(b.iban, 4) AS masked_iban,

    -- 7. Performance & KPIs
    ISNULL(ks.total_evaluation_months, 0) AS kpi_evaluation_months,
    ISNULL(ks.overall_avg_kpi_score, 0.00) AS overall_avg_kpi_score,
    ISNULL(ks.target_achievement_pct, 0.00) AS overall_target_achievement_pct,
    CASE 
        WHEN ks.overall_avg_kpi_score >= 90 THEN 'Tier 1 - Outstanding'
        WHEN ks.overall_avg_kpi_score >= 75 THEN 'Tier 2 - Meets Expectations'
        WHEN ks.overall_avg_kpi_score IS NOT NULL THEN 'Tier 3 - Needs Improvement'
        ELSE 'Not Evaluated'
    END AS kpi_performance_tier,

    -- 8. Sales & Commissions
    ISNULL(cs.total_sales_generated_egp, 0.00) AS total_sales_generated_egp,
    ISNULL(cs.total_commission_earned_egp, 0.00) AS total_commission_earned_egp,
    ISNULL(cs.avg_commission_rate_pct, 0.00) AS effective_commission_rate_pct,

    -- 9. Attendance & Reliability
    ISNULL(att.total_work_days_logged, 0) AS total_attendance_days,
    ISNULL(att.days_present, 0) AS days_present,
    ISNULL(att.days_absent, 0) AS days_absent,
    ROUND((ISNULL(att.days_present, 0) * 100.0 / NULLIF(ISNULL(att.total_work_days_logged, 0), 0)), 2) AS attendance_reliability_pct,
    ISNULL(att.avg_hours_per_present_day, 0.00) AS avg_hours_per_day,
    ISNULL(att.remote_work_ratio_pct, 0.00) AS remote_work_ratio_pct

FROM employees e
INNER JOIN departments d 
    ON e.department_id = d.department_id
INNER JOIN roles r 
    ON e.role_id = r.role_id
LEFT JOIN employees m 
    ON e.manager_id = m.employee_id
LEFT JOIN employee_bank_accounts b 
    ON e.employee_id = b.employee_id
LEFT JOIN role_perms_agg rp 
    ON r.role_id = rp.role_id
LEFT JOIN kpi_summary ks 
    ON e.employee_id = ks.employee_id
LEFT JOIN commission_summary cs 
    ON e.employee_id = cs.employee_id
LEFT JOIN attendance_metrics att 
    ON e.employee_id = att.employee_id;
GO

-- =====================================================================
-- Diagnostic Execution Queries to Heavily Test View Performance
-- =====================================================================

-- Query 1: Top Performers across Departments (High KPI + High Attendance)
SELECT TOP 15
    department_name,
    full_name,
    role_title,
    salary,
    dept_salary_rank,
    overall_avg_kpi_score,
    overall_target_achievement_pct,
    attendance_reliability_pct,
    kpi_performance_tier
FROM vw_enterprise_hr_360_analytics
WHERE is_active = 1 
  AND overall_avg_kpi_score >= 85.00
  AND attendance_reliability_pct >= 90.00
ORDER BY overall_avg_kpi_score DESC, attendance_reliability_pct DESC;
GO

-- Query 2: Sales Department Commission Yield & Budget Utilization
SELECT TOP 10
    full_name,
    role_title,
    salary,
    total_sales_generated_egp,
    total_commission_earned_egp,
    effective_commission_rate_pct,
    ROUND((total_commission_earned_egp * 100.0 / NULLIF(department_annual_budget_egp, 0)), 4) AS pct_of_dept_budget_drawn
FROM vw_enterprise_hr_360_analytics
WHERE department_name = 'Sales' AND total_commission_earned_egp > 0
ORDER BY total_commission_earned_egp DESC;
GO

-- Query 3: Edge Case Fixture Audit (Null Salaries & Unassigned Managers)
SELECT 
    employee_id,
    full_name,
    department_name,
    role_title,
    salary,
    manager_name,
    overall_avg_kpi_score
FROM vw_enterprise_hr_360_analytics
WHERE salary IS NULL OR manager_name IS NULL
ORDER BY salary ASC, employee_id ASC;
GO

-- Query 4: Execution Profiling (I/O & CPU Statistics)
SET STATISTICS TIME, IO ON;
GO

SELECT 
    department_name,
    COUNT(*) AS active_staff,
    ROUND(AVG(salary), 2) AS dept_avg_salary,
    ROUND(AVG(overall_avg_kpi_score), 2) AS dept_avg_kpi,
    ROUND(AVG(attendance_reliability_pct), 2) AS dept_avg_attendance
FROM vw_enterprise_hr_360_analytics
WHERE is_active = 1
GROUP BY department_name
ORDER BY dept_avg_kpi DESC;
GO

SET STATISTICS TIME, IO OFF;
GO
