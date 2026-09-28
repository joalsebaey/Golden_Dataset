;WITH distinct_perms AS (
    SELECT DISTINCT role_id, permission_name
    FROM role_permissions
    WHERE is_allowed = 1
),
role_perms AS (
    SELECT role_id, STRING_AGG(permission_name, ', ') WITHIN GROUP (ORDER BY permission_name) AS permissions
    FROM distinct_perms
    GROUP BY role_id
),
kpis AS (
    SELECT employee_id, period_month, AVG(score) AS score
    FROM employee_kpis
    WHERE period_month = '2025-09-01'
    GROUP BY employee_id, period_month
),
comms AS (
    SELECT employee_id, SUM(commission_amount) AS total_amount
    FROM commissions
    GROUP BY employee_id
)
SELECT TOP (5)
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    d.department_name,
    r.role_title,
    rp.permissions,
    b.bank_name,
    b.iban,
    k.period_month AS latest_kpi_period,
    k.score AS latest_kpi_score,
    ISNULL(c.total_amount, 0.00) AS total_commissions,
    DATEDIFF(YEAR, e.hire_date, GETDATE()) - 
        CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.hire_date, GETDATE()), e.hire_date) > GETDATE() THEN 1 ELSE 0 END AS years_tenure,
    e.is_active
FROM employees e
INNER JOIN departments d 
    ON e.department_id = d.department_id
INNER JOIN roles r 
    ON e.role_id = r.role_id
LEFT JOIN role_perms rp 
    ON r.role_id = rp.role_id
LEFT JOIN employee_bank_accounts b 
    ON e.employee_id = b.employee_id
LEFT JOIN kpis k 
    ON e.employee_id = k.employee_id
LEFT JOIN comms c 
    ON e.employee_id = c.employee_id
WHERE e.is_active = 1
ORDER BY e.employee_id;