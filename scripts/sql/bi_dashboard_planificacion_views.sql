-- =============================================================================
-- Capa semántica BI: Dashboard Planificación (Power BI / Superset)
-- Fuente única de verdad para KPIs, evolución mensual y probabilidad.
-- Repo: superset-analytics — aplicar con scripts/apply-bi-views.sh
-- =============================================================================

-- Real del año anterior a nivel empresa (base de crecimiento % en vista anual)
CREATE OR REPLACE VIEW bi_v_real_anterior_empresa AS
SELECT
    year + 1 AS year,
    company_name AS empresa,
    SUM(invoice) AS facturacion_real_anterior
FROM bc_job_ledger_entry_month
GROUP BY year, company_name;

-- -----------------------------------------------------------------------------
-- KPI detalle por empresa / año / departamento
-- Planificación Actual (PBI Resumen) = tipo P + tipo R (suma).
-- PSI 2026: 3.685.687 + 2.688.861 = 6.374.548 €. Ni híbrido ni solo P.
-- + real año anterior (Ingresos) por departamento (Crecimiento %)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_v_planificacion_kpi AS
WITH plan_actual AS (
    SELECT
        f.empresa,
        f.year,
        f.departamento AS department_code,
        SUM(f.facturado) AS plan_facturacion,
        SUM(f.coste) AS plan_coste,
        SUM(f.facturado - f.coste) AS plan_beneficio
    FROM v_se_facturacion f
    WHERE f.tipo IN ('P', 'R')
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
),
real_anterior_dept AS (
    SELECT
        company_name AS empresa,
        year + 1 AS year,
        departamento AS department_code,
        SUM(invoice) AS facturacion_real_anterior
    FROM bc_job_ledger_entry_month
    WHERE concepto_analitico_descripcion = 'Ingresos'
    GROUP BY company_name, year + 1, departamento
)
SELECT
    COALESCE(obj.empresa, plan_actual.empresa) AS empresa,
    COALESCE(obj.year, plan_actual.year) AS year,
    COALESCE(obj.department_code, plan_actual.department_code) AS department_code,
    d.department_name,
    obj.obj_facturacion,
    obj.obj_coste,
    obj.obj_beneficio,
    CASE
        WHEN obj.obj_facturacion > 0
            THEN (obj.obj_facturacion - obj.obj_coste) / obj.obj_facturacion * 100
    END AS obj_margen_pct,
    COALESCE(plan_actual.plan_facturacion, 0) AS plan_facturacion,
    COALESCE(plan_actual.plan_coste, 0) AS plan_coste,
    COALESCE(plan_actual.plan_beneficio, 0) AS plan_beneficio,
    CASE
        WHEN COALESCE(plan_actual.plan_facturacion, 0) > 0
            THEN plan_actual.plan_beneficio / plan_actual.plan_facturacion * 100
    END AS plan_margen_pct,
    ra.facturacion_real_anterior,
    CASE
        WHEN ra.facturacion_real_anterior > 0
            THEN (obj.obj_facturacion - ra.facturacion_real_anterior)
                 / ra.facturacion_real_anterior * 100
    END AS obj_crecimiento_pct,
    CASE
        WHEN ra.facturacion_real_anterior > 0
            THEN (COALESCE(plan_actual.plan_facturacion, 0) - ra.facturacion_real_anterior)
                 / ra.facturacion_real_anterior * 100
    END AS plan_crecimiento_pct
FROM obj
FULL OUTER JOIN plan_actual
    ON obj.empresa = plan_actual.empresa
   AND obj.year = plan_actual.year
   AND obj.department_code = plan_actual.department_code
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = COALESCE(obj.empresa, plan_actual.empresa)
   AND d.department_code = COALESCE(obj.department_code, plan_actual.department_code)
LEFT JOIN real_anterior_dept ra
    ON ra.empresa = COALESCE(obj.empresa, plan_actual.empresa)
   AND ra.year = COALESCE(obj.year, plan_actual.year)
   AND ra.department_code = COALESCE(obj.department_code, plan_actual.department_code);

-- Evolución mensual (tablas y gráficos + fuente de valores de filtros nativos)
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

-- Facturación por probabilidad (gráfico de barras — panel Resumen PBI)
-- PBI: % = probability=0 → 100; resto = probability. Total = P + R.
-- PSI 2026 bucket 100%: ~5.707 mil €
CREATE OR REPLACE VIEW bi_v_facturacion_probabilidad AS
SELECT
    f.empresa,
    f.year,
    f.departamento AS department_code,
    d.department_name,
    CASE
        WHEN COALESCE(f.probability, 0) = 0 THEN 100::numeric
        ELSE COALESCE(f.probability, 0)
    END AS probabilidad,
    SUM(f.facturado) AS facturacion
FROM v_se_facturacion f
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = f.empresa
   AND d.department_code = f.departamento
WHERE f.tipo IN ('P', 'R')
GROUP BY
    f.empresa,
    f.year,
    f.departamento,
    d.department_name,
    CASE
        WHEN COALESCE(f.probability, 0) = 0 THEN 100::numeric
        ELSE COALESCE(f.probability, 0)
    END;

COMMENT ON VIEW bi_v_planificacion_kpi IS
  'KPIs Objetivos/Plan por dept (Planificación Actual = P+R; crecimiento vs Ingresos año ant.). Filtro Departamento OK.';
COMMENT ON VIEW bi_v_evolucion_mensual IS
  'Evolución mensual facturación/coste/margen por tipo P o R. Fuente de filtros Año/Empresa/Dept/Tipo.';
COMMENT ON VIEW bi_v_facturacion_probabilidad IS
  'Facturación P+R por probabilidad (0→100 como PBI). Panel Resumen.';

-- -----------------------------------------------------------------------------
-- Resumen por proyecto (página PBI «Resumen Proyectos»)
-- Filtros PBI visual: tipo_proyecto = Operational; estado IN (Completed,Open,Planning)
--   (= excluye Lost). Con PSI 2026: Fact 6.374.548 / Coste 4.350.042 / Margen 31,76 %.
-- Encabezado = job || ' --- ' || left(descripcion,36) — ya en v_se_facturacion.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_v_resumen_proyectos AS
SELECT
    f.empresa,
    f.year,
    f.departamento AS department_code,
    d.department_name,
    f.tipo,
    f.tipo_proyecto,
    f.estado,
    f.job,
    f.encabezado AS proyecto,
    SUM(f.facturado) AS facturacion,
    SUM(f.coste) AS coste,
    CASE
        WHEN SUM(f.facturado) > 0
            THEN (SUM(f.facturado) - SUM(f.coste)) / SUM(f.facturado) * 100
    END AS margen_pct
FROM v_se_facturacion f
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = f.empresa
   AND d.department_code = f.departamento
WHERE f.tipo IN ('P', 'R')
  AND f.tipo_proyecto = 'Operational'
  AND COALESCE(f.estado, '') IN ('Completed', 'Open', 'Planning')
GROUP BY
    f.empresa,
    f.year,
    f.departamento,
    d.department_name,
    f.tipo,
    f.tipo_proyecto,
    f.estado,
    f.job,
    f.encabezado
-- PBI «Filtro no es 0»: excluir filas sin importe ni coste
HAVING ABS(SUM(f.facturado)) > 0.0001 OR ABS(SUM(f.coste)) > 0.0001;

COMMENT ON VIEW bi_v_resumen_proyectos IS
  'Resumen Proyectos PBI: Operational + Completed/Open/Planning; excluye filas 0/0.';

-- -----------------------------------------------------------------------------
-- Unidad / Gastos (página PBI «Unidad»)
-- Pivot coste por concepto analítico × mes. Filtro de página PBI: Structure.
-- Dims year/empresa/department_code/tipo para filtros nativos del dashboard.
-- TRIM(descripcion_ca) unifica duplicados por espacios en BC.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_v_unidad AS
SELECT
    c.empresa,
    c.year,
    c.departamento AS department_code,
    d.department_name,
    c.tipo,
    c.tipo_proyecto,
    TRIM(c.descripcion_ca) AS concepto_analitico,
    SUM(c.coste) FILTER (WHERE c.month = 1) AS m01,
    SUM(c.coste) FILTER (WHERE c.month = 2) AS m02,
    SUM(c.coste) FILTER (WHERE c.month = 3) AS m03,
    SUM(c.coste) FILTER (WHERE c.month = 4) AS m04,
    SUM(c.coste) FILTER (WHERE c.month = 5) AS m05,
    SUM(c.coste) FILTER (WHERE c.month = 6) AS m06,
    SUM(c.coste) FILTER (WHERE c.month = 7) AS m07,
    SUM(c.coste) FILTER (WHERE c.month = 8) AS m08,
    SUM(c.coste) FILTER (WHERE c.month = 9) AS m09,
    SUM(c.coste) FILTER (WHERE c.month = 10) AS m10,
    SUM(c.coste) FILTER (WHERE c.month = 11) AS m11,
    SUM(c.coste) FILTER (WHERE c.month = 12) AS m12,
    SUM(c.coste) AS total
FROM v_se_coste c
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = c.empresa
   AND d.department_code = c.departamento
WHERE c.tipo_proyecto = 'Structure'
  AND COALESCE(TRIM(c.descripcion_ca), '') <> ''
GROUP BY
    c.empresa,
    c.year,
    c.departamento,
    d.department_name,
    c.tipo,
    c.tipo_proyecto,
    TRIM(c.descripcion_ca)
HAVING ABS(SUM(c.coste)) > 0.0001;

COMMENT ON VIEW bi_v_unidad IS
  'Unidad/Gastos PBI: coste por concepto×mes; tipo_proyecto=Structure fijo.';

-- KPI agregados por empresa/año (referencia / legacy; tarjetas usan bi_v_planificacion_kpi)
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
