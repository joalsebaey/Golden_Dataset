-- =====================================================================
-- 04_cte_query.sql - PostgreSQL CTE (Common Table Expression) Suite
-- Tests both Recursive CTE graph traversal and Multi-Stage Analytical CTEs.
-- =====================================================================

SET search_path TO public;

-- =====================================================================
-- Part A: Recursive CTE - Organizational Hierarchy & Span of Control
-- Traverses self-referencing foreign key (manager_id) to calculate depth,
-- build hierarchical lineage breadcrumb paths, and compute span of control.
-- =====================================================================
WITH RECURSIVE org_hierarchy AS (
    -- Anchor Member: Executive leadership (no manager assigned)
    SELECT 
        e.employee_id,
        e.first_name || ' ' || e.last_name AS employee_name,
        e.manager_id,
        CAST(NULL AS TEXT) AS manager_name,
        1 AS org_level,
        CAST(e.first_name || ' ' || e.last_name AS TEXT) AS hierarchy_path,
        e.department_id,
        e.role_id,
        e.salary
    FROM employees e
    WHERE e.manager_id IS NULL AND e.is_active = 1

    UNION ALL

    -- Recursive Member: Subordinates reporting to managers from previous level
    SELECT 
        e.employee_id,
        e.first_name || ' ' || e.last_name AS employee_name,
        e.manager_id,
        oh.employee_name AS manager_name,
        oh.org_level + 1 AS org_level,
        oh.hierarchy_path || ' -> ' || e.first_name || ' ' || e.last_name AS hierarchy_path,
        e.department_id,
        e.role_id,
        e.salary
    FROM employees e
    INNER JOIN org_hierarchy oh 
        ON e.manager_id = oh.employee_id
    WHERE e.is_active = 1
),
direct_reports AS (
    -- Span of control calculation per manager
    SELECT 
        manager_id, 
        COUNT(*) AS direct_report_count
    FROM employees
    WHERE is_active = 1 AND manager_id IS NOT NULL
    GROUP BY manager_id
)
SELECT 
    oh.employee_id,
    oh.employee_name,
    d.department_name,
    r.role_title,
    COALESCE(oh.manager_name, '<< Executive / Board Level >>') AS manager_name,
    oh.org_level,
    COALESCE(dr.direct_report_count, 0) AS direct_reports_count,
    oh.salary,
    oh.hierarchy_path
FROM org_hierarchy oh
INNER JOIN departments d 
    ON oh.department_id = d.department_id
INNER JOIN roles r 
    ON oh.role_id = r.role_id
LEFT JOIN direct_reports dr 
    ON oh.employee_id = dr.manager_id
ORDER BY oh.org_level ASC, direct_reports_count DESC, oh.employee_id ASC
LIMIT 20;

-- =====================================================================
-- Part B: Multi-Stage Analytical CTE - Salary Benchmarks & Window Ranking
-- Combines 4 CTEs to analyze departmental salary variance, window ranks,
-- and individual attendance reliability over 324K+ records.
-- =====================================================================
WITH dept_salary_stats AS (
    -- CTE 1: Baseline departmental compensation statistics
    SELECT 
        department_id,
        COUNT(*) AS total_employees,
        AVG(salary) AS avg_dept_salary,
        MIN(salary) AS min_dept_salary,
        MAX(salary) AS max_dept_salary
    FROM employees
    WHERE is_active = 1 AND salary IS NOT NULL
    GROUP BY department_id
),
emp_salary_ranking AS (
    -- CTE 2: Window rankings: salary rank & percentile within each department
    SELECT 
        e.employee_id,
        e.first_name || ' ' || e.last_name AS employee_name,
        e.department_id,
        e.role_id,
        e.salary,
        dss.avg_dept_salary,
        ROUND(e.salary - dss.avg_dept_salary, 2) AS diff_from_dept_avg,
        DENSE_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary DESC) AS dept_salary_rank,
        ROUND((PERCENT_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary ASC))::numeric, 4) AS dept_salary_percentile
    FROM employees e
    INNER JOIN dept_salary_stats dss 
        ON e.department_id = dss.department_id
    WHERE e.is_active = 1 AND e.salary IS NOT NULL
),
kpi_performance AS (
    -- CTE 3: Employee-level KPI achievement aggregation
    SELECT 
        employee_id,
        COUNT(*) AS total_kpi_reviews,
        ROUND(AVG(score), 2) AS avg_kpi_score,
        ROUND(SUM(actual) / NULLIF(SUM(target), 0) * 100.0, 2) AS overall_target_achievement_pct
    FROM employee_kpis
    GROUP BY employee_id
),
attendance_summary AS (
    -- CTE 4: Attendance reliability & hours over 324,449 records
    SELECT 
        employee_id,
        COUNT(*) AS total_work_days,
        SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS days_present,
        SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) AS days_absent,
        SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END) AS days_leave,
        ROUND(AVG(CASE WHEN status = 'present' THEN hours_worked END), 2) AS avg_daily_hours
    FROM attendance
    GROUP BY employee_id
)
SELECT 
    d.department_name,
    esr.employee_name,
    r.role_title,
    esr.salary,
    esr.dept_salary_rank,
    esr.diff_from_dept_avg,
    COALESCE(kp.avg_kpi_score, 0.00) AS avg_kpi_score,
    COALESCE(kp.overall_target_achievement_pct, 0.00) AS target_achievement_pct,
    att.total_work_days,
    att.days_present,
    ROUND((att.days_present * 100.0 / NULLIF(att.total_work_days, 0)), 2) AS attendance_reliability_pct,
    att.avg_daily_hours
FROM emp_salary_ranking esr
INNER JOIN departments d 
    ON esr.department_id = d.department_id
INNER JOIN roles r 
    ON esr.role_id = r.role_id
LEFT JOIN kpi_performance kp 
    ON esr.employee_id = kp.employee_id
LEFT JOIN attendance_summary att 
    ON esr.employee_id = att.employee_id
WHERE esr.dept_salary_rank <= 3  -- Top 3 earners in every department
ORDER BY d.department_name ASC, esr.dept_salary_rank ASC;
