-- =====================================================================
-- 05_complex_view.sql - PostgreSQL Complicated VIEW & Engine Optimizer Stress Test
-- Builds a comprehensive 8-table enterprise analytical VIEW integrating window functions,
-- string aggregations, pre-aggregated CTEs, and multi-metric employee scoring.
-- =====================================================================

SET search_path TO public;

-- Clean teardown of view if previously created
DROP VIEW IF EXISTS v_enterprise_hr_360_analytics CASCADE;

-- ---------------------------------------------------------------------
-- Create Complicated 360-Degree Analytical View
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_enterprise_hr_360_analytics AS
WITH role_perms_agg AS (
    -- Subquery 1: Aggregated permissions per role
    SELECT 
        role_id,
        STRING_AGG(DISTINCT permission_name, ', ' ORDER BY permission_name) AS permissions_list,
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
    e.first_name || ' ' || e.last_name AS full_name,
    e.email,
    e.hire_date,
    e.termination_date,
    e.is_active,
    e.work_mode AS primary_work_mode,
    EXTRACT(YEAR FROM AGE(COALESCE(e.termination_date, CURRENT_DATE), e.hire_date)) AS tenure_years,

    -- 2. Managerial Hierarchy
    e.manager_id,
    m.first_name || ' ' || m.last_name AS manager_name,

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
    COALESCE(rp.permissions_list, 'None') AS assigned_permissions,
    COALESCE(rp.total_permissions_granted, 0) AS permissions_count,

    -- 5. Compensation & Window Analytics
    e.salary,
    ROUND(e.salary - AVG(e.salary) OVER (PARTITION BY e.department_id), 2) AS salary_diff_from_dept_avg,
    DENSE_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary DESC NULLS LAST) AS dept_salary_rank,
    ROUND((PERCENT_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary ASC NULLS FIRST))::numeric, 4) AS dept_salary_percentile,

    -- 6. Banking Detail (Masked IBAN for security)
    b.bank_name,
    CONCAT(SUBSTRING(b.iban, 1, 4), '****', SUBSTRING(b.iban, LENGTH(b.iban) - 3, 4)) AS masked_iban,

    -- 7. Performance & KPIs
    COALESCE(ks.total_evaluation_months, 0) AS kpi_evaluation_months,
    COALESCE(ks.overall_avg_kpi_score, 0.00) AS overall_avg_kpi_score,
    COALESCE(ks.target_achievement_pct, 0.00) AS overall_target_achievement_pct,
    CASE 
        WHEN ks.overall_avg_kpi_score >= 90 THEN 'Tier 1 - Outstanding'
        WHEN ks.overall_avg_kpi_score >= 75 THEN 'Tier 2 - Meets Expectations'
        WHEN ks.overall_avg_kpi_score IS NOT NULL THEN 'Tier 3 - Needs Improvement'
        ELSE 'Not Evaluated'
    END AS kpi_performance_tier,

    -- 8. Sales & Commissions
    COALESCE(cs.total_sales_generated_egp, 0.00) AS total_sales_generated_egp,
    COALESCE(cs.total_commission_earned_egp, 0.00) AS total_commission_earned_egp,
    COALESCE(cs.avg_commission_rate_pct, 0.00) AS effective_commission_rate_pct,

    -- 9. Attendance & Reliability
    COALESCE(att.total_work_days_logged, 0) AS total_attendance_days,
    COALESCE(att.days_present, 0) AS days_present,
    COALESCE(att.days_absent, 0) AS days_absent,
    ROUND((COALESCE(att.days_present, 0) * 100.0 / NULLIF(COALESCE(att.total_work_days_logged, 0), 0)), 2) AS attendance_reliability_pct,
    COALESCE(att.avg_hours_per_present_day, 0.00) AS avg_hours_per_day,
    COALESCE(att.remote_work_ratio_pct, 0.00) AS remote_work_ratio_pct

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

-- =====================================================================
-- Diagnostic Execution Queries to Heavily Test View Performance
-- =====================================================================

-- Query 1: Top Performers across Departments (High KPI + High Attendance)
SELECT 
    department_name,
    full_name,
    role_title,
    salary,
    dept_salary_rank,
    overall_avg_kpi_score,
    overall_target_achievement_pct,
    attendance_reliability_pct,
    kpi_performance_tier
FROM v_enterprise_hr_360_analytics
WHERE is_active = 1 
  AND overall_avg_kpi_score >= 85.00
  AND attendance_reliability_pct >= 90.00
ORDER BY overall_avg_kpi_score DESC, attendance_reliability_pct DESC
LIMIT 15;

-- Query 2: Sales Department Commission Yield & Budget Utilization
SELECT 
    full_name,
    role_title,
    salary,
    total_sales_generated_egp,
    total_commission_earned_egp,
    effective_commission_rate_pct,
    ROUND((total_commission_earned_egp * 100.0 / NULLIF(department_annual_budget_egp, 0)), 4) AS pct_of_dept_budget_drawn
FROM v_enterprise_hr_360_analytics
WHERE department_name = 'Sales' AND total_commission_earned_egp > 0
ORDER BY total_commission_earned_egp DESC
LIMIT 10;

-- Query 3: Edge Case Fixture Audit (Null Salaries & Unassigned Managers)
SELECT 
    employee_id,
    full_name,
    department_name,
    role_title,
    salary,
    manager_name,
    overall_avg_kpi_score
FROM v_enterprise_hr_360_analytics
WHERE salary IS NULL OR manager_name IS NULL
ORDER BY salary ASC NULLS FIRST, employee_id ASC;

-- Query 4: Query Plan Inspection (Optimizer Unfolding & Index Pushdown)
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    department_name,
    COUNT(*) AS active_staff,
    ROUND(AVG(salary), 2) AS dept_avg_salary,
    ROUND(AVG(overall_avg_kpi_score), 2) AS dept_avg_kpi,
    ROUND(AVG(attendance_reliability_pct), 2) AS dept_avg_attendance
FROM v_enterprise_hr_360_analytics
WHERE is_active = 1
GROUP BY department_name
ORDER BY dept_avg_kpi DESC;
