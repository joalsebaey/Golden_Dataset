-- =====================================================================
-- SQL Server Test 6: Performance Benchmark - 324K Attendance Aggregation & MoM Trend
-- Stresses T-SQL execution engine on heavy joins, group-by, and window LAG() functions
-- SET STATISTICS TIME, IO ON allows evaluating CPU time, elapsed time, and scan counts.
-- =====================================================================

SET STATISTICS TIME, IO ON;

;WITH monthly_attendance AS (
    -- Heavy group-by scan across 324,449 attendance records joined with employees
    SELECT 
        e.department_id,
        CONVERT(VARCHAR(7), a.work_date, 120) AS work_month,
        a.work_mode,
        COUNT(*) AS total_records,
        SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
        SUM(CASE WHEN a.status = 'absent' THEN 1 ELSE 0 END) AS absent_count,
        SUM(CASE WHEN a.status = 'leave' THEN 1 ELSE 0 END) AS leave_count,
        ROUND(SUM(a.hours_worked), 2) AS total_hours_worked,
        ROUND(AVG(a.hours_worked), 2) AS avg_hours_per_day
    FROM attendance a
    INNER JOIN employees e ON a.employee_id = e.employee_id
    GROUP BY e.department_id, CONVERT(VARCHAR(7), a.work_date, 120), a.work_mode
),
department_monthly_totals AS (
    -- Rollup to department level per month
    SELECT 
        department_id,
        work_month,
        SUM(total_records) AS dept_monthly_records,
        SUM(present_count) AS dept_monthly_present,
        SUM(absent_count) AS dept_monthly_absent,
        SUM(total_hours_worked) AS dept_monthly_hours,
        ROUND(SUM(present_count) * 100.0 / NULLIF(SUM(total_records), 0), 2) AS dept_attendance_pct
    FROM monthly_attendance
    GROUP BY department_id, work_month
),
ranked_trends AS (
    -- Window function MoM delta and cross-department monthly rank
    SELECT 
        d.department_name,
        dmt.work_month,
        dmt.dept_monthly_records,
        dmt.dept_monthly_present,
        dmt.dept_attendance_pct,
        dmt.dept_monthly_hours,
        LAG(dmt.dept_attendance_pct, 1) OVER (PARTITION BY dmt.department_id ORDER BY dmt.work_month) AS prev_month_attendance_pct,
        ROUND(dmt.dept_attendance_pct - LAG(dmt.dept_attendance_pct, 1) OVER (PARTITION BY dmt.department_id ORDER BY dmt.work_month), 2) AS mom_attendance_pct_change,
        DENSE_RANK() OVER (PARTITION BY dmt.work_month ORDER BY dmt.dept_attendance_pct DESC) AS monthly_dept_rank
    FROM department_monthly_totals dmt
    INNER JOIN departments d ON dmt.department_id = d.department_id
)
SELECT TOP (30)
    department_name,
    work_month,
    dept_monthly_records,
    dept_monthly_present,
    dept_attendance_pct,
    prev_month_attendance_pct,
    mom_attendance_pct_change,
    dept_monthly_hours,
    monthly_dept_rank
FROM ranked_trends
WHERE work_month >= '2025-01'
ORDER BY work_month DESC, monthly_dept_rank ASC;

SET STATISTICS TIME, IO OFF;
