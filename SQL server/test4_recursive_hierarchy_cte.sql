-- =====================================================================
-- SQL Server Test 4: Recursive CTE - Organizational Hierarchy & Span of Control
-- T-SQL Recursive CTE traversing manager_id, calculating hierarchy depth,
-- building breadcrumb path, and calculating direct report span of control.
-- =====================================================================

;WITH org_hierarchy AS (
    -- Anchor member: Top-level directors/executives (no manager assigned)
    SELECT 
        e.employee_id,
        CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
        e.manager_id,
        CAST(NULL AS NVARCHAR(MAX)) AS manager_name,
        1 AS org_level,
        CAST(CONCAT(e.first_name, ' ', e.last_name) AS NVARCHAR(MAX)) AS hierarchy_path,
        e.department_id,
        e.role_id,
        e.salary
    FROM employees e
    WHERE e.manager_id IS NULL AND e.is_active = 1

    UNION ALL

    -- Recursive member: Employees reporting to managers in preceding level
    SELECT 
        e.employee_id,
        CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
        e.manager_id,
        oh.employee_name AS manager_name,
        oh.org_level + 1 AS org_level,
        CONCAT(oh.hierarchy_path, N' -> ', e.first_name, ' ', e.last_name) AS hierarchy_path,
        e.department_id,
        e.role_id,
        e.salary
    FROM employees e
    INNER JOIN org_hierarchy oh ON e.manager_id = oh.employee_id
    WHERE e.is_active = 1
),
direct_reports AS (
    -- Direct reports count per manager
    SELECT 
        manager_id, 
        COUNT(*) AS report_count
    FROM employees
    WHERE is_active = 1 AND manager_id IS NOT NULL
    GROUP BY manager_id
)
SELECT TOP (15)
    oh.employee_id,
    oh.employee_name,
    d.department_name,
    r.role_title,
    oh.manager_name,
    oh.org_level,
    ISNULL(dr.report_count, 0) AS direct_reports_count,
    oh.salary,
    oh.hierarchy_path
FROM org_hierarchy oh
INNER JOIN departments d ON oh.department_id = d.department_id
INNER JOIN roles r ON oh.role_id = r.role_id
LEFT JOIN direct_reports dr ON oh.employee_id = dr.manager_id
ORDER BY oh.org_level ASC, direct_reports_count DESC, oh.salary DESC;
