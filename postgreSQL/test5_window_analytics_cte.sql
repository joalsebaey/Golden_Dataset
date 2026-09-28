-- =====================================================================
-- PostgreSQL Test 5: Multi-CTE 360-Degree Department Analytics & Window Functions
-- Tests complex CTEs, window functions (DENSE_RANK, PERCENT_RANK),
-- cross-table aggregations across employees, KPIs, and 324K attendance records.
-- =====================================================================

SET search_path TO tenant_1;

WITH dept_salary_stats AS (
    -- Baseline departmental compensation statistics
    SELECT 
        department_id,
        COUNT(*) AS total_employees,
        AVG(salary) AS avg_dept_salary,
        MIN(salary) AS min_dept_salary,
        MAX(salary) AS max_dept_salary
    FROM employees
    WHERE is_active = TRUE AND salary IS NOT NULL
    GROUP BY department_id
),
emp_salary_ranking AS (
    -- Window rankings: salary rank & percentile within each department
    SELECT 
        e.employee_id,
        e.first_name || ' ' || e.last_name AS employee_name,
        e.department_id,
        e.role_id,
        e.salary,
        dss.avg_dept_salary,
        ROUND(e.salary - dss.avg_dept_salary, 2) AS diff_from_dept_avg,
        DENSE_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary DESC) AS dept_salary_rank,
        PERCENT_RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary ASC) AS dept_salary_percentile
    FROM employees e
    INNER JOIN dept_salary_stats dss ON e.department_id = dss.department_id
    WHERE e.is_active = TRUE AND e.salary IS NOT NULL
),
kpi_performance AS (
    -- Employee-level KPI achievement aggregation
    SELECT 
        employee_id,
        COUNT(*) AS total_kpi_reviews,
        ROUND(AVG(score), 2) AS avg_kpi_score,
        ROUND(SUM(actual) / NULLIF(SUM(target), 0) * 100.0, 2) AS overall_target_achievement_pct
    FROM employee_kpis
    GROUP BY employee_id
),
attendance_summary AS (
    -- Attendance reliability & hours over 324K records
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
    r.level AS role_level,
    esr.salary,
    esr.diff_from_dept_avg,
    esr.dept_salary_rank,
    ROUND(CAST(esr.dept_salary_percentile * 100 AS NUMERIC), 1) AS salary_percentile,
    kp.avg_kpi_score,
    kp.overall_target_achievement_pct,
    ROUND(att.days_present * 100.0 / NULLIF(att.total_work_days, 0), 1) AS attendance_rate_pct,
    att.avg_daily_hours
FROM emp_salary_ranking esr
INNER JOIN departments d ON esr.department_id = d.department_id
INNER JOIN roles r ON esr.role_id = r.role_id
LEFT JOIN kpi_performance kp ON esr.employee_id = kp.employee_id
LEFT JOIN attendance_summary att ON esr.employee_id = att.employee_id
WHERE esr.dept_salary_rank <= 3
ORDER BY d.department_name, esr.dept_salary_rank
LIMIT 20;
