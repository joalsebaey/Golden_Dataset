---- =====================================================================
-- PostgreSQL Test 6: Performance Benchmark - Attendance Aggregation & MoM Trend
-- =====================================================================

-- 1. إضافة public إلى مسار البحث حتى يعثر المحرك على الجداول أياً كان مكانها
SET search_path TO tenant_1, public;

EXPLAIN (ANALYZE, BUFFERS)
WITH monthly_attendance AS (
    -- تجميع سجلات الحضور والانصراف شهرياً حسب الإدارة
    SELECT 
        e.department_id,
        TO_CHAR(a.work_date, 'YYYY-MM') AS work_month,
        a.work_mode,
        COUNT(*) AS total_records,
        SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
        SUM(CASE WHEN a.status = 'absent' THEN 1 ELSE 0 END) AS absent_count,
        SUM(CASE WHEN a.status = 'leave' THEN 1 ELSE 0 END) AS leave_count,
        ROUND(SUM(a.hours_worked)::numeric, 2) AS total_hours_worked,
        ROUND(AVG(a.hours_worked)::numeric, 2) AS avg_hours_per_day
    FROM attendance a
    INNER JOIN employees e ON a.employee_id = e.employee_id
    GROUP BY e.department_id, TO_CHAR(a.work_date, 'YYYY-MM'), a.work_mode
),
department_monthly_totals AS (
    -- تجميع الإجماليات على مستوى الإدارة والشهر
    SELECT 
        department_id,
        work_month,
        SUM(total_records) AS dept_monthly_records,
        SUM(present_count) AS dept_monthly_present,
        SUM(absent_count) AS dept_monthly_absent,
        SUM(total_hours_worked) AS dept_monthly_hours,
        ROUND((SUM(present_count) * 100.0 / NULLIF(SUM(total_records), 0))::numeric, 2) AS dept_attendance_pct
    FROM monthly_attendance
    GROUP BY department_id, work_month
),
ranked_trends AS (
    -- حساب نسبة التغير الشهري MoM وترتيب الإدارات
    SELECT 
        d.department_name,
        dmt.work_month,
        dmt.dept_monthly_records,
        dmt.dept_monthly_present,
        dmt.dept_attendance_pct,
        dmt.dept_monthly_hours,
        LAG(dmt.dept_attendance_pct, 1) OVER (PARTITION BY dmt.department_id ORDER BY dmt.work_month) AS prev_month_attendance_pct,
        ROUND((dmt.dept_attendance_pct - LAG(dmt.dept_attendance_pct, 1) OVER (PARTITION BY dmt.department_id ORDER BY dmt.work_month))::numeric, 2) AS mom_attendance_pct_change,
        DENSE_RANK() OVER (PARTITION BY dmt.work_month ORDER BY dmt.dept_attendance_pct DESC) AS monthly_dept_rank
    FROM department_monthly_totals dmt
    INNER JOIN departments d ON dmt.department_id = d.department_id
)
SELECT 
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
ORDER BY work_month DESC, monthly_dept_rank ASC
LIMIT 30;