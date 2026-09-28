-- =====================================================================
-- PostgreSQL Test 4: Recursive CTE - Organizational Hierarchy & Span of Control
-- Tests recursive graph traversal over self-referencing foreign key (manager_id),
-- hierarchy depth calculation, lineage path concatenation, and direct report aggregation.
-- =====================================================================

SET search_path TO public;

WITH RECURSIVE org_hierarchy AS (
    -- Anchor member: Top-level directors/executives (no manager assigned)
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
    WHERE e.manager_id IS NULL AND e.is_active = TRUE

    UNION ALL

    -- Recursive member: Employees reporting to managers in preceding level
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
    INNER JOIN org_hierarchy oh ON e.manager_id = oh.employee_id
    WHERE e.is_active = TRUE
),
direct_reports AS (
    -- Span of control calculation per manager
    SELECT 
        manager_id, 
        COUNT(*) AS report_count
    FROM employees
    WHERE is_active = TRUE AND manager_id IS NOT NULL
    GROUP BY manager_id
)
SELECT 
    oh.employee_id,
    oh.employee_name,
    d.department_name,
    r.role_title,
    oh.manager_name,
    oh.org_level,
    COALESCE(dr.report_count, 0) AS direct_reports_count,
    oh.salary,
    oh.hierarchy_path
FROM org_hierarchy oh
INNER JOIN departments d ON oh.department_id = d.department_id
INNER JOIN roles r ON oh.role_id = r.role_id
LEFT JOIN direct_reports dr ON oh.employee_id = dr.manager_id
ORDER BY oh.org_level ASC, direct_reports_count DESC, oh.salary DESC
LIMIT 15;
