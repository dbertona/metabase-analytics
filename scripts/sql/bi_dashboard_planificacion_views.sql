-- =============================================================================
-- Capa semántica BI: Dashboard Planificación (Power BI / Superset)
-- Fuente única de verdad para KPIs, evolución mensual y probabilidad.
-- =============================================================================

-- Real del año anterior a nivel empresa (base de crecimiento %)
CREATE OR REPLACE VIEW bi_v_real_anterior_empresa AS
SELECT
    year + 1 AS year,
    company_name AS empresa,
    SUM(invoice) AS facturacion_real_anterior
FROM bc_job_ledger_entry_month
GROUP BY year, company_name;

-- -----------------------------------------------------------------------------
-- KPI detalle por empresa / año / departamento
-- Planificación Actual (PBI):
--   mes cerrado (proyecto-mes en bc_meses_cerrados) → tipo R
--   mes abierto → tipo P
-- Objetivos: v_se_objectives
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_v_planificacion_kpi AS
WITH closed_job_months AS (
    SELECT DISTINCT
        company_name AS empresa,
        job_no AS job,
        year,
        month
    FROM bc_meses_cerrados
    WHERE job_no IS NOT NULL
      AND btrim(job_no::text) <> ''
),
plan_hybrid AS (
    SELECT
        f.empresa,
        f.year,
        f.departamento AS department_code,
        SUM(f.facturado) AS plan_facturacion,
        SUM(f.coste) AS plan_coste,
        SUM(f.facturado - f.coste) AS plan_beneficio
    FROM v_se_facturacion f
    LEFT JOIN closed_job_months c
        ON c.empresa = f.empresa
       AND c.job = f.job
       AND c.year = f.year
       AND c.month = f.month
    WHERE (
            c.empresa IS NOT NULL AND f.tipo = 'R'
        ) OR (
            c.empresa IS NULL AND f.tipo = 'P'
        )
    GROUP BY f.empresa, f.year, f.departamento
),
obj AS (
    SELECT
        o.empresa,
        o.ano AS year,
        o.departamento AS department_code,
        o.billing_target AS obj_facturacion,
        o.cost_target AS obj_coste,
        o.beneficio_eur AS obj_beneficio
    FROM v_se_objectives o
)
SELECT
    COALESCE(obj.empresa, plan_hybrid.empresa) AS empresa,
    COALESCE(obj.year, plan_hybrid.year) AS year,
    COALESCE(obj.department_code, plan_hybrid.department_code) AS department_code,
    d.department_name,
    obj.obj_facturacion,
    obj.obj_coste,
    obj.obj_beneficio,
    CASE
        WHEN obj.obj_facturacion > 0
            THEN (obj.obj_facturacion - obj.obj_coste) / obj.obj_facturacion * 100
    END AS obj_margen_pct,
    COALESCE(plan_hybrid.plan_facturacion, 0) AS plan_facturacion,
    COALESCE(plan_hybrid.plan_coste, 0) AS plan_coste,
    COALESCE(plan_hybrid.plan_beneficio, 0) AS plan_beneficio,
    CASE
        WHEN COALESCE(plan_hybrid.plan_facturacion, 0) > 0
            THEN plan_hybrid.plan_beneficio / plan_hybrid.plan_facturacion * 100
    END AS plan_margen_pct
FROM obj
FULL OUTER JOIN plan_hybrid
    ON obj.empresa = plan_hybrid.empresa
   AND obj.year = plan_hybrid.year
   AND obj.department_code = plan_hybrid.department_code
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = COALESCE(obj.empresa, plan_hybrid.empresa)
   AND d.department_code = COALESCE(obj.department_code, plan_hybrid.department_code);

-- Evolución mensual (tablas y gráficos)
CREATE OR REPLACE VIEW bi_v_evolucion_mensual AS
SELECT
    r.empresa,
    r.year,
    r.month,
    r.ano_mes,
    r.codigo_unico_departamento,
    split_part(r.codigo_unico_departamento, ':', 2) AS department_code,
    d.department_name,
    r.tipo,
    r.total_venta AS facturacion,
    r.total_gasto AS coste,
    r.margen_eur AS beneficio,
    r.margen_pct
FROM v_se_resumen_mensual r
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = r.empresa
   AND d.department_code = split_part(r.codigo_unico_departamento, ':', 2);

-- Facturación por probabilidad (gráfico de barras)
CREATE OR REPLACE VIEW bi_v_facturacion_probabilidad AS
SELECT
    f.empresa,
    f.year,
    f.departamento AS department_code,
    d.department_name,
    COALESCE(f.probability, 0) AS probabilidad,
    SUM(f.facturado) AS facturacion
FROM v_se_facturacion f
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = f.empresa
   AND d.department_code = f.departamento
WHERE f.tipo = 'P'
GROUP BY
    f.empresa,
    f.year,
    f.departamento,
    d.department_name,
    COALESCE(f.probability, 0);

COMMENT ON VIEW bi_v_planificacion_kpi IS
  'KPIs Objetivos y Planificación Actual: mes cerrado (bc_meses_cerrados) = R, mes abierto = P.';
COMMENT ON VIEW bi_v_evolucion_mensual IS
  'Evolución mensual facturación/coste/margen por tipo P o R.';
COMMENT ON VIEW bi_v_facturacion_probabilidad IS
  'Facturación planificada agrupada por probabilidad de cierre.';

-- KPI agregados por empresa/año (tarjetas del dashboard)
CREATE OR REPLACE VIEW bi_v_kpi_anual_empresa AS
WITH agg AS (
    SELECT
        k.empresa,
        k.year,
        SUM(k.obj_facturacion) AS obj_facturacion,
        SUM(k.obj_coste) AS obj_coste,
        SUM(k.obj_beneficio) AS obj_beneficio,
        SUM(k.plan_facturacion) AS plan_facturacion,
        SUM(k.plan_coste) AS plan_coste,
        SUM(k.plan_beneficio) AS plan_beneficio
    FROM bi_v_planificacion_kpi k
    GROUP BY k.empresa, k.year
)
SELECT
    a.empresa,
    a.year,
    a.obj_facturacion,
    a.obj_coste,
    a.obj_beneficio,
    CASE
        WHEN a.obj_facturacion > 0
            THEN a.obj_beneficio / a.obj_facturacion * 100
    END AS obj_margen_pct,
    a.plan_facturacion,
    a.plan_coste,
    a.plan_beneficio,
    CASE
        WHEN a.plan_facturacion > 0
            THEN a.plan_beneficio / a.plan_facturacion * 100
    END AS plan_margen_pct,
    ra.facturacion_real_anterior,
    CASE
        WHEN ra.facturacion_real_anterior > 0
            THEN (a.obj_facturacion - ra.facturacion_real_anterior)
                 / ra.facturacion_real_anterior * 100
    END AS obj_crecimiento_pct,
    CASE
        WHEN ra.facturacion_real_anterior > 0
            THEN (a.plan_facturacion - ra.facturacion_real_anterior)
                 / ra.facturacion_real_anterior * 100
    END AS plan_crecimiento_pct
FROM agg a
LEFT JOIN bi_v_real_anterior_empresa ra
    ON ra.empresa = a.empresa
   AND ra.year = a.year;

COMMENT ON VIEW bi_v_kpi_anual_empresa IS
  'KPIs anuales por empresa con crecimiento vs real año anterior (PBI).';
