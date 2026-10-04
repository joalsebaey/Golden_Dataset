-- =====================================================================
-- 06_kpi_commission_joins.sql - MySQL Advanced JOINs, KPIs & Commission Analytics
-- Executes multi-table JOINs across employees, departments, roles, commissions, and KPIs.
-- Evaluates sales commission payouts, KPI achievement ratios, MoM trends, and edge cases.
-- =====================================================================

-- =====================================================================
-- Test Case 1: Individual Sales Performance - Commissions vs KPI Scores
-- Evaluates whether top sales commission earners also achieve high KPI scores.
-- =====================================================================
WITH sales_kpis AS (
    SELECT 
        employee_id,
        ROUND(AVG(score), 2) AS avg_kpi_score,
        ROUND(MIN(score), 2) AS min_kpi_score,
        ROUND(MAX(score), 2) AS max_kpi_score,
        ROUND(SUM(actual) / NULLIF(SUM(target), 0) * 100.0, 2) AS target_achievement_pct,
        COUNT(*) AS total_kpi_evaluations
    FROM employee_kpis
    GROUP BY employee_id
),
sales_commissions AS (
    SELECT 
        employee_id,
        COUNT(DISTINCT period_month) AS commission_months_count,
        ROUND(SUM(sales_amount_egp), 2) AS total_sales_volume_egp,
        ROUND(SUM(commission_amount), 2) AS total_commission_paid_egp,
        ROUND(AVG(commission_amount), 2) AS avg_monthly_commission_egp
    FROM commissions
    GROUP BY employee_id
)
SELECT 
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS sales_representative,
    r.role_title,
    e.salary,
    sc.total_sales_volume_egp,
    sc.total_commission_paid_egp,
    sc.avg_monthly_commission_egp,
    sk.avg_kpi_score,
    sk.target_achievement_pct,
    -- Performance Classification
    CASE 
        WHEN sk.avg_kpi_score >= 85 AND sc.total_commission_paid_egp >= 150000 THEN 'Elite Performer (High KPI + High Sales)'
        WHEN sc.total_commission_paid_egp >= 150000 THEN 'High Producer (Sales Focused)'
        WHEN sk.avg_kpi_score >= 85 THEN 'Quality Focused (High KPI, Modest Sales)'
        ELSE 'Standard Performer'
    END AS sales_performance_tier
FROM employees e
INNER JOIN departments d 
    ON e.department_id = d.department_id
INNER JOIN roles r 
    ON e.role_id = r.role_id
INNER JOIN sales_commissions sc 
    ON e.employee_id = sc.employee_id
LEFT JOIN sales_kpis sk 
    ON e.employee_id = sk.employee_id
WHERE d.department_name = 'Sales' AND e.is_active = 1
ORDER BY sc.total_commission_paid_egp DESC, sk.avg_kpi_score DESC
LIMIT 15;

-- =====================================================================
-- Test Case 2: Department-Level Executive Summary
-- Evaluates budget utilization, total compensation, commission costs, and avg KPIs.
-- =====================================================================
WITH dept_kpis AS (
    SELECT 
        e.department_id,
        ROUND(AVG(k.score), 2) AS dept_avg_kpi_score,
        ROUND(SUM(k.actual) / NULLIF(SUM(k.target), 0) * 100.0, 2) AS dept_kpi_achievement_pct
    FROM employee_kpis k
    INNER JOIN employees e ON k.employee_id = e.employee_id
    GROUP BY e.department_id
),
dept_commissions AS (
    SELECT 
        e.department_id,
        ROUND(SUM(c.sales_amount_egp), 2) AS dept_total_sales_egp,
        ROUND(SUM(c.commission_amount), 2) AS dept_total_commissions_egp
    FROM commissions c
    INNER JOIN employees e ON c.employee_id = e.employee_id
    GROUP BY e.department_id
),
dept_staffing AS (
    SELECT 
        department_id,
        COUNT(*) AS total_headcount,
        SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) AS active_headcount,
        ROUND(SUM(CASE WHEN is_active = 1 THEN salary ELSE 0 END), 2) AS total_active_salary_egp
    FROM employees
    GROUP BY department_id
)
SELECT 
    d.department_id,
    d.department_name,
    d.budget_egp AS annual_budget_egp,
    ds.active_headcount,
    ds.total_active_salary_egp,
    IFNULL(dc.dept_total_sales_egp, 0.00) AS dept_total_sales_egp,
    IFNULL(dc.dept_total_commissions_egp, 0.00) AS dept_total_commissions_egp,
    ROUND((IFNULL(dc.dept_total_commissions_egp, 0.00) * 100.0 / NULLIF(d.budget_egp, 0)), 2) AS commission_budget_share_pct,
    IFNULL(dk.dept_avg_kpi_score, 0.00) AS dept_avg_kpi_score,
    IFNULL(dk.dept_kpi_achievement_pct, 0.00) AS dept_kpi_achievement_pct
FROM departments d
INNER JOIN dept_staffing ds ON d.department_id = ds.department_id
LEFT JOIN dept_commissions dc ON d.department_id = dc.department_id
LEFT JOIN dept_kpis dk ON d.department_id = dk.department_id
ORDER BY d.budget_egp DESC;

-- =====================================================================
-- Test Case 3: Month-over-Month (MoM) Trend of Sales Commissions & KPIs
-- Evaluates time-series window functions (LAG) tracking monthly performance changes.
-- =====================================================================
WITH monthly_sales_metrics AS (
    SELECT 
        c.period_month,
        COUNT(DISTINCT c.employee_id) AS active_sales_reps,
        ROUND(SUM(c.sales_amount_egp), 2) AS total_monthly_sales_egp,
        ROUND(SUM(c.commission_amount), 2) AS total_monthly_commissions_egp,
        ROUND(AVG(k.score), 2) AS monthly_sales_avg_kpi
    FROM commissions c
    LEFT JOIN employee_kpis k 
        ON c.employee_id = k.employee_id AND c.period_month = k.period_month
    GROUP BY c.period_month
)
SELECT 
    period_month,
    active_sales_reps,
    total_monthly_sales_egp,
    total_monthly_commissions_egp,
    monthly_sales_avg_kpi,
    LAG(total_monthly_sales_egp, 1) OVER (ORDER BY period_month) AS prev_month_sales_egp,
    ROUND(total_monthly_sales_egp - LAG(total_monthly_sales_egp, 1) OVER (ORDER BY period_month), 2) AS mom_sales_change_egp,
    ROUND((total_monthly_sales_egp - LAG(total_monthly_sales_egp, 1) OVER (ORDER BY period_month)) * 100.0 / 
          NULLIF(LAG(total_monthly_sales_egp, 1) OVER (ORDER BY period_month), 0), 2) AS mom_sales_growth_pct
FROM monthly_sales_metrics
ORDER BY period_month ASC;

-- =====================================================================
-- Test Case 4: Edge Cases & Business Invariants Verification
-- Checks:
--   4a) Verify that non-sales employees have 0 commissions.
--   4b) Verify NULL salary handling does not break aggregations.
--   4c) Verify active vs terminated employees KPI performance.
-- =====================================================================

-- 4a: Non-Sales employees commission check (Must return 0 rows)
SELECT 
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    d.department_name,
    c.commission_amount
FROM commissions c
INNER JOIN employees e ON c.employee_id = e.employee_id
INNER JOIN departments d ON e.department_id = d.department_id
WHERE d.department_name <> 'Sales';

-- 4b: NULL salary handling test (Confirm 5 intentional fixture employees)
SELECT 
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    d.department_name,
    r.role_title,
    e.salary,
    ROUND(AVG(k.score), 2) AS avg_kpi_score
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id
INNER JOIN roles r ON e.role_id = r.role_id
LEFT JOIN employee_kpis k ON e.employee_id = k.employee_id
WHERE e.salary IS NULL
GROUP BY e.employee_id, e.first_name, e.last_name, d.department_name, r.role_title, e.salary
ORDER BY e.employee_id;

-- 4c: Active vs Terminated Personnel KPI comparison
SELECT 
    e.is_active,
    COUNT(DISTINCT e.employee_id) AS employee_count,
    ROUND(AVG(k.score), 2) AS avg_kpi_score,
    ROUND(SUM(k.actual) / NULLIF(SUM(k.target), 0) * 100.0, 2) AS overall_target_achievement_pct
FROM employees e
LEFT JOIN employee_kpis k ON e.employee_id = k.employee_id
GROUP BY e.is_active
ORDER BY e.is_active DESC;
