-- =====================================================================
-- HR Schema (MySQL) - Single tenant
-- Governed Schema aligned with schema.jpeg, dataset (*.csv), and Golden Evaluation Dataset
-- Compatible with MySQL 8.0+ (InnoDB, UTF8MB4)
-- =====================================================================

-- Clean teardown in reverse dependency order
DROP TABLE IF EXISTS employee_kpis;
DROP TABLE IF EXISTS commissions;
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS attendance;
DROP TABLE IF EXISTS employee_bank_accounts;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS departments;

-- ---------------------------------------------------------------------
-- 1) departments
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id    INT AUTO_INCREMENT PRIMARY KEY,
    department_name  VARCHAR(100) NOT NULL UNIQUE,
    budget_egp       DECIMAL(14,2) NOT NULL,
    location         VARCHAR(100) NULL,
    CONSTRAINT chk_dept_budget CHECK (budget_egp >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 2) roles
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id          INT AUTO_INCREMENT PRIMARY KEY,
    department_id    INT NOT NULL,
    role_title       VARCHAR(100) NOT NULL,
    level            SMALLINT NOT NULL,
    salary_band_min  DECIMAL(12,2) NOT NULL,
    salary_band_max  DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_roles_level CHECK (level BETWEEN 1 AND 10),
    CONSTRAINT chk_roles_salary_band CHECK (salary_band_max >= salary_band_min),
    CONSTRAINT fk_roles_department FOREIGN KEY (department_id) REFERENCES departments(department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_roles_department ON roles(department_id);

-- ---------------------------------------------------------------------
-- 3) employees
--    first_name / last_name contain Arabic or English (utf8mb4)
--    commission_pct: 5.00 for Sales employees, 0 for everyone else
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id       INT AUTO_INCREMENT PRIMARY KEY,
    first_name        VARCHAR(100) NOT NULL,
    last_name         VARCHAR(100) NOT NULL,
    email             VARCHAR(255) NOT NULL UNIQUE,
    department_id     INT NOT NULL,
    role_id           INT NOT NULL,
    salary            DECIMAL(12,2) NULL,   -- NULL allowed (NULL-handling fixture)
    commission_pct    DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    hire_date         DATE NOT NULL,
    termination_date  DATE NULL,
    is_active         TINYINT(1) NOT NULL DEFAULT 1,
    work_mode         VARCHAR(10) NOT NULL,
    manager_id        INT NULL,
    CONSTRAINT chk_emp_salary CHECK (salary IS NULL OR salary >= 0),
    CONSTRAINT chk_emp_commission_pct CHECK (commission_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_emp_work_mode CHECK (work_mode IN ('onsite', 'remote', 'hybrid')),
    CONSTRAINT chk_emp_termination CHECK (termination_date IS NULL OR termination_date >= hire_date),
    CONSTRAINT chk_emp_manager CHECK (manager_id IS NULL OR manager_id <> employee_id),
    CONSTRAINT fk_emp_department FOREIGN KEY (department_id) REFERENCES departments(department_id),
    CONSTRAINT fk_emp_role FOREIGN KEY (role_id) REFERENCES roles(role_id),
    CONSTRAINT fk_emp_manager FOREIGN KEY (manager_id) REFERENCES employees(employee_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_employees_department ON employees(department_id);
CREATE INDEX idx_employees_role       ON employees(role_id);
CREATE INDEX idx_employees_manager    ON employees(manager_id);
CREATE INDEX idx_employees_active     ON employees(is_active);

-- Guard: commission_pct > 0 is only allowed for the Sales department
DELIMITER $$

DROP TRIGGER IF EXISTS trg_employees_commission_sales_insert$$
CREATE TRIGGER trg_employees_commission_sales_insert
BEFORE INSERT ON employees
FOR EACH ROW
BEGIN
    IF NEW.commission_pct > 0 AND NOT EXISTS (
        SELECT 1 FROM departments d
        WHERE d.department_id = NEW.department_id AND d.department_name = 'Sales'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'commission_pct > 0 is allowed only for Sales employees';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_employees_commission_sales_update$$
CREATE TRIGGER trg_employees_commission_sales_update
BEFORE UPDATE ON employees
FOR EACH ROW
BEGIN
    IF NEW.commission_pct > 0 AND NOT EXISTS (
        SELECT 1 FROM departments d
        WHERE d.department_id = NEW.department_id AND d.department_name = 'Sales'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'commission_pct > 0 is allowed only for Sales employees';
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 4) employee_bank_accounts (1-to-1 relationship with employees)
-- ---------------------------------------------------------------------
CREATE TABLE employee_bank_accounts (
    bank_account_id  INT AUTO_INCREMENT PRIMARY KEY,
    employee_id      INT NOT NULL UNIQUE,
    bank_name        VARCHAR(100) NOT NULL,
    iban             VARCHAR(34) NOT NULL UNIQUE,
    account_number   VARCHAR(30) NOT NULL,
    CONSTRAINT fk_bank_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- ---------------------------------------------------------------------
-- 5) attendance
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id     INT NOT NULL,
    work_date       DATE NOT NULL,
    status          VARCHAR(15) NOT NULL,   -- e.g. present / absent / leave
    hours_worked    DECIMAL(4,2) NULL,      -- NULL unless present
    work_mode       VARCHAR(10) NULL,       -- NULL unless present
    CONSTRAINT uq_att_employee_date UNIQUE (employee_id, work_date),
    CONSTRAINT chk_att_hours CHECK (hours_worked IS NULL OR (hours_worked BETWEEN 0 AND 24)),
    CONSTRAINT chk_att_work_mode CHECK (work_mode IS NULL OR work_mode IN ('onsite', 'remote', 'hybrid')),
    CONSTRAINT chk_att_status_consistency CHECK (
        (status = 'present' AND hours_worked IS NOT NULL AND work_mode IS NOT NULL) OR
        (status <> 'present' AND hours_worked IS NULL AND work_mode IS NULL)
    ),
    CONSTRAINT fk_att_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_attendance_date ON attendance(work_date);

-- ---------------------------------------------------------------------
-- 6) role_permissions
-- ---------------------------------------------------------------------
CREATE TABLE role_permissions (
    permission_id    INT AUTO_INCREMENT PRIMARY KEY,
    role_id          INT NOT NULL,
    permission_name  VARCHAR(100) NOT NULL,
    access_level     VARCHAR(20) NOT NULL,  -- e.g. read / write / admin
    is_allowed       TINYINT(1) NOT NULL DEFAULT 0,
    CONSTRAINT uq_role_permission UNIQUE (role_id, permission_name),
    CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 7) commissions - actual monthly commission for Sales employees
-- ---------------------------------------------------------------------
CREATE TABLE commissions (
    commission_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id        INT NOT NULL,
    period_month       DATE NOT NULL,
    sales_amount_egp   DECIMAL(14,2) NOT NULL,
    commission_pct     DECIMAL(5,2) NOT NULL DEFAULT 5.00,
    commission_amount  DECIMAL(14,2) NOT NULL,
    CONSTRAINT uq_comm_employee_period UNIQUE (employee_id, period_month),
    CONSTRAINT chk_comm_sales CHECK (sales_amount_egp >= 0),
    CONSTRAINT chk_comm_pct CHECK (commission_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_comm_period_day CHECK (DAY(period_month) = 1),
    CONSTRAINT chk_comm_amount_calc CHECK (commission_amount = ROUND(sales_amount_egp * commission_pct / 100, 2)),
    CONSTRAINT fk_comm_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_commissions_period ON commissions(period_month);

-- ---------------------------------------------------------------------
-- 8) employee_kpis - flexible monthly KPIs for all departments
-- ---------------------------------------------------------------------
CREATE TABLE employee_kpis (
    kpi_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id   INT NOT NULL,
    period_month  DATE NOT NULL,
    kpi_name      VARCHAR(100) NOT NULL,
    target        DECIMAL(14,2) NOT NULL,
    actual        DECIMAL(14,2) NOT NULL,
    score         DECIMAL(5,2) NOT NULL,
    CONSTRAINT uq_kpi_employee_period_name UNIQUE (employee_id, period_month, kpi_name),
    CONSTRAINT chk_kpi_period_day CHECK (DAY(period_month) = 1),
    CONSTRAINT chk_kpi_score CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT fk_kpi_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_kpis_period ON employee_kpis(period_month);
CREATE INDEX idx_kpis_name   ON employee_kpis(kpi_name);