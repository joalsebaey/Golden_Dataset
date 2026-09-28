WITH role_perms AS (
    SELECT role_id, GROUP_CONCAT(DISTINCT permission_name ORDER BY permission_name SEPARATOR ', ') AS permissions
    FROM role_permissions
    WHERE is_allowed = 1
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
SELECT 
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    d.department_name,
    r.role_title,
    rp.permissions,
    b.bank_name,
    b.iban,
    k.period_month AS latest_kpi_period,
    k.score AS latest_kpi_score,
    IFNULL(c.total_amount, 0.00) AS total_commissions,
    TIMESTAMPDIFF(YEAR, e.hire_date, CURDATE()) AS years_tenure,
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
ORDER BY e.employee_id
LIMIT 5;