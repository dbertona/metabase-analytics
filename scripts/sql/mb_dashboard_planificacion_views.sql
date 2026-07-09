-- =============================================================================
-- Vistas Metabase: Dashboard Planificación PS Analytics
-- Réplica del dashboard Power BI (Objetivos / Planificación / Real)
-- =============================================================================

-- Cierre de planificación más reciente por año (tipo P)
CREATE OR REPLACE VIEW mb_v_cierre_planificacion AS
SELECT
    year,
    MAX(closing_month_code) AS closing_month_code
FROM bc_historico_planificacion_mes
WHERE type_line = 'P'
GROUP BY year;

-- Dimensión: empresas
CREATE OR REPLACE VIEW mb_v_dim_empresa AS
SELECT DISTINCT company_name
FROM bc_department
WHERE company_name IS NOT NULL
ORDER BY company_name;

-- Dimensión: departamentos
CREATE OR REPLACE VIEW mb_v_dim_departamento AS
SELECT
    company_name,
    code AS department_code,
    name AS department_name
FROM bc_department
ORDER BY company_name, name;

-- Dimensión: años disponibles
CREATE OR REPLACE VIEW mb_v_dim_anio AS
SELECT DISTINCT year
FROM (
    SELECT year FROM bc_objectives_by_department
    UNION
    SELECT year FROM bc_historico_planificacion_mes
    UNION
    SELECT year FROM bc_job_ledger_entry_month
) y
ORDER BY year DESC;

-- -----------------------------------------------------------------------------
-- KPI: Objetivos anuales por empresa y departamento
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW mb_v_kpi_objetivos AS
SELECT
    o.year,
    o.company_name,
    o.department_code,
    d.department_name,
    o.billing_target AS facturacion,
    o.cost_target AS coste,
    o.billing_target - o.cost_target AS beneficio,
    CASE
        WHEN o.billing_target > 0
            THEN (o.billing_target - o.cost_target) / o.billing_target * 100
    END AS margen_pct
FROM bc_objectives_by_department o
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = o.company_name
   AND d.department_code = o.department_code;

-- Facturación real del año anterior por departamento
CREATE OR REPLACE VIEW mb_v_real_anio_anterior AS
SELECT
    year + 1 AS year,
    company_name,
    departamento AS department_code,
    SUM(invoice) AS facturacion_real_anterior
FROM bc_job_ledger_entry_month
GROUP BY year, company_name, departamento;

-- Facturación real del año anterior a nivel empresa (base de crecimiento %)
CREATE OR REPLACE VIEW mb_v_real_anio_anterior_empresa AS
SELECT
    year + 1 AS year,
    company_name,
    SUM(invoice) AS facturacion_real_anterior
FROM bc_job_ledger_entry_month
GROUP BY year, company_name;

-- -----------------------------------------------------------------------------
-- KPI: Planificación actual (tipo P, último cierre del año)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW mb_v_kpi_planificacion AS
SELECT
    h.year,
    h.company_name,
    h.departamento AS department_code,
    d.department_name,
    SUM(h.invoice) AS facturacion,
    SUM(h.cost) AS coste,
    SUM(h.invoice) - SUM(h.cost) AS beneficio,
    CASE
        WHEN SUM(h.invoice) > 0
            THEN (SUM(h.invoice) - SUM(h.cost)) / SUM(h.invoice) * 100
    END AS margen_pct,
    c.closing_month_code
FROM bc_historico_planificacion_mes h
JOIN mb_v_cierre_planificacion c
    ON c.year = h.year
   AND c.closing_month_code = h.closing_month_code
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = h.company_name
   AND d.department_code = h.departamento
WHERE h.type_line = 'P'
  AND COALESCE(h.status, '') NOT IN ('Lost')
GROUP BY
    h.year,
    h.company_name,
    h.departamento,
    d.department_name,
    c.closing_month_code;

-- -----------------------------------------------------------------------------
-- KPI: Real (tipo R, movimientos contables mensuales)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW mb_v_kpi_real AS
SELECT
    r.year,
    r.company_name,
    r.departamento AS department_code,
    d.department_name,
    SUM(r.invoice) AS facturacion,
    SUM(r.cost) AS coste,
    SUM(r.invoice) - SUM(r.cost) AS beneficio,
    CASE
        WHEN SUM(r.invoice) > 0
            THEN (SUM(r.invoice) - SUM(r.cost)) / SUM(r.invoice) * 100
    END AS margen_pct
FROM bc_job_ledger_entry_month r
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = r.company_name
   AND d.department_code = r.departamento
GROUP BY
    r.year,
    r.company_name,
    r.departamento,
    d.department_name;

-- -----------------------------------------------------------------------------
-- KPI agregados con crecimiento (para tarjetas del dashboard)
-- seccion: Objetivos Anuales | Planificación Actual | Real
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW mb_v_dashboard_kpi AS
WITH objetivos AS (
    SELECT
        o.year,
        o.company_name,
        o.department_code,
        o.department_name,
        'Objetivos Anuales' AS seccion,
        o.facturacion,
        o.coste,
        o.beneficio,
        o.margen_pct,
        CASE
            WHEN rae.facturacion_real_anterior > 0
                THEN (o.facturacion - rae.facturacion_real_anterior)
                     / rae.facturacion_real_anterior * 100
        END AS crecimiento_pct
    FROM mb_v_kpi_objetivos o
    LEFT JOIN mb_v_real_anio_anterior_empresa rae
        ON rae.year = o.year
       AND rae.company_name = o.company_name
),
planificacion AS (
    SELECT
        p.year,
        p.company_name,
        p.department_code,
        p.department_name,
        'Planificación Actual' AS seccion,
        p.facturacion,
        p.coste,
        p.beneficio,
        p.margen_pct,
        CASE
            WHEN rae.facturacion_real_anterior > 0
                THEN (p.facturacion - rae.facturacion_real_anterior)
                     / rae.facturacion_real_anterior * 100
        END AS crecimiento_pct
    FROM mb_v_kpi_planificacion p
    LEFT JOIN mb_v_real_anio_anterior_empresa rae
        ON rae.year = p.year
       AND rae.company_name = p.company_name
),
real AS (
    SELECT
        r.year,
        r.company_name,
        r.department_code,
        r.department_name,
        'Real' AS seccion,
        r.facturacion,
        r.coste,
        r.beneficio,
        r.margen_pct,
        CASE
            WHEN rae.facturacion_real_anterior > 0
                THEN (r.facturacion - rae.facturacion_real_anterior)
                     / rae.facturacion_real_anterior * 100
        END AS crecimiento_pct
    FROM mb_v_kpi_real r
    LEFT JOIN mb_v_real_anio_anterior_empresa rae
        ON rae.year = r.year
       AND rae.company_name = r.company_name
)
SELECT * FROM objetivos
UNION ALL
SELECT * FROM planificacion
UNION ALL
SELECT * FROM real;

-- -----------------------------------------------------------------------------
-- Evolución mensual (gráficos inferiores)
-- tipo: P = Planificación | R = Real
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW mb_v_evolucion_mensual AS
SELECT
    'P' AS tipo,
    h.company_name,
    h.year,
    h.month,
    h.departamento AS department_code,
    d.department_name,
    SUM(h.invoice) AS facturacion,
    SUM(h.cost) AS coste,
    SUM(h.invoice) - SUM(h.cost) AS beneficio,
    CASE
        WHEN SUM(h.invoice) > 0
            THEN (SUM(h.invoice) - SUM(h.cost)) / SUM(h.invoice) * 100
    END AS margen_pct,
    h.closing_month_code
FROM bc_historico_planificacion_mes h
JOIN mb_v_cierre_planificacion c
    ON c.year = h.year
   AND c.closing_month_code = h.closing_month_code
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = h.company_name
   AND d.department_code = h.departamento
WHERE h.type_line = 'P'
  AND COALESCE(h.status, '') NOT IN ('Lost')
GROUP BY
    h.company_name,
    h.year,
    h.month,
    h.departamento,
    d.department_name,
    h.closing_month_code

UNION ALL

SELECT
    'R' AS tipo,
    r.company_name,
    r.year,
    r.month,
    r.departamento,
    d.department_name,
    SUM(r.invoice),
    SUM(r.cost),
    SUM(r.invoice) - SUM(r.cost),
    CASE
        WHEN SUM(r.invoice) > 0
            THEN (SUM(r.invoice) - SUM(r.cost)) / SUM(r.invoice) * 100
    END,
    NULL::varchar
FROM bc_job_ledger_entry_month r
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = r.company_name
   AND d.department_code = r.departamento
GROUP BY
    r.company_name,
    r.year,
    r.month,
    r.departamento,
    d.department_name;

-- Resumen tabular (facturación / coste / beneficio / margen por sección)
CREATE OR REPLACE VIEW mb_v_resumen AS
SELECT
    year,
    company_name,
    department_code,
    department_name,
    seccion,
    facturacion,
    coste,
    beneficio,
    margen_pct,
    crecimiento_pct
FROM mb_v_dashboard_kpi;

COMMENT ON VIEW mb_v_dashboard_kpi IS 'KPIs agregados para dashboard Metabase (Objetivos, Planificación, Real)';
COMMENT ON VIEW mb_v_evolucion_mensual IS 'Evolución mensual P/R para gráficos de facturación y margen';
