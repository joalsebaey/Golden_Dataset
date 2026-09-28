SET search_path TO tenant_1;

SELECT 
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    a.work_date,
    a.status AS attendance_status,
    a.hours_worked,
    a.work_mode
FROM attendance a
INNER JOIN employees e 
    ON a.employee_id = e.employee_id
ORDER BY a.work_date DESC, e.employee_id ASC
LIMIT 10;