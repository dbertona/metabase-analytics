-- =============================================================================
-- Capa semántica BI: Dashboard Planificación (Power BI / Superset)
-- Fuente única de verdad para KPIs, evolución mensual y probabilidad.
-- Repo: superset-analytics — aplicar con scripts/apply-bi-views.sh
--
-- Rendimiento (2026-07-29): vistas pesadas = MATERIALIZED VIEW bi_mv_* +
-- wrapper bi_v_* (mismos nombres en Superset / RLS Jinja).
-- REFRESH tras sync 004 (nodo "Refresh BI Materialized Views") o:
--   ./scripts/apply-bi-views.sh --refresh
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
-- Drop wrappers + MVs (dependientes primero)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS bi_v_kpi_anual_empresa CASCADE;
DROP VIEW IF EXISTS bi_v_planificacion_kpi CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_planificacion_kpi CASCADE;
DROP VIEW IF EXISTS bi_v_evolucion_mensual CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_evolucion_mensual CASCADE;
DROP VIEW IF EXISTS bi_v_facturacion_probabilidad CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_facturacion_probabilidad CASCADE;
DROP VIEW IF EXISTS bi_v_resumen_proyectos CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_resumen_proyectos CASCADE;
DROP VIEW IF EXISTS bi_v_unidad CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_unidad CASCADE;
DROP VIEW IF EXISTS bi_v_gastos CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_gastos CASCADE;
DROP VIEW IF EXISTS bi_v_mano_obra CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_mano_obra CASCADE;
DROP VIEW IF EXISTS bi_v_facturacion CASCADE;
DROP MATERIALIZED VIEW IF EXISTS bi_mv_facturacion CASCADE;

-- -----------------------------------------------------------------------------
-- bi_v_planificacion_kpi  ←  wrapper sobre bi_mv_planificacion_kpi
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_planificacion_kpi AS
WITH plan_actual AS (
    SELECT
        f.empresa,
        f.year,
        f.departamento AS department_code,
        f.tipo,
        CASE f.tipo
            WHEN 'P' THEN 'Planificado'
            WHEN 'R' THEN 'Real'
            ELSE COALESCE(f.tipo::text, '')
        END AS tipo_label,
        SUM(f.facturado) AS plan_facturacion,
        SUM(f.coste) AS plan_coste,
        SUM(f.facturado - f.coste) AS plan_beneficio
    FROM v_se_facturacion f
    WHERE f.tipo IN ('P', 'R')
    GROUP BY f.empresa, f.year, f.departamento, f.tipo
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
    plan_actual.empresa,
    plan_actual.year,
    plan_actual.department_code,
    d.department_name,
    plan_actual.tipo,
    plan_actual.tipo_label,
    -- Objetivos solo en P: evita duplicar SUM(obj_*) cuando hay P+R
    CASE WHEN plan_actual.tipo = 'P' THEN obj.obj_facturacion END AS obj_facturacion,
    CASE WHEN plan_actual.tipo = 'P' THEN obj.obj_coste END AS obj_coste,
    CASE WHEN plan_actual.tipo = 'P' THEN obj.obj_beneficio END AS obj_beneficio,
    CASE
        WHEN plan_actual.tipo = 'P' AND obj.obj_facturacion > 0
            THEN (obj.obj_facturacion - obj.obj_coste) / obj.obj_facturacion * 100
    END AS obj_margen_pct,
    COALESCE(plan_actual.plan_facturacion, 0) AS plan_facturacion,
    COALESCE(plan_actual.plan_coste, 0) AS plan_coste,
    COALESCE(plan_actual.plan_beneficio, 0) AS plan_beneficio,
    CASE
        WHEN COALESCE(plan_actual.plan_facturacion, 0) > 0
            THEN plan_actual.plan_beneficio / plan_actual.plan_facturacion * 100
    END AS plan_margen_pct,
    -- Real anterior en todas las filas tipo (Plan Δ% divide por COUNT DISTINCT tipo)
    ra.facturacion_real_anterior,
    CASE
        WHEN plan_actual.tipo = 'P' AND ra.facturacion_real_anterior > 0
            THEN (obj.obj_facturacion - ra.facturacion_real_anterior)
                 / ra.facturacion_real_anterior * 100
    END AS obj_crecimiento_pct,
    CASE
        WHEN ra.facturacion_real_anterior > 0
            THEN (COALESCE(plan_actual.plan_facturacion, 0) - ra.facturacion_real_anterior)
                 / ra.facturacion_real_anterior * 100
    END AS plan_crecimiento_pct
FROM plan_actual
LEFT JOIN obj
    ON obj.empresa = plan_actual.empresa
   AND obj.year = plan_actual.year
   AND obj.department_code = plan_actual.department_code
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = plan_actual.empresa
   AND d.department_code = plan_actual.department_code
LEFT JOIN real_anterior_dept ra
    ON ra.empresa = plan_actual.empresa
   AND ra.year = plan_actual.year
   AND ra.department_code = plan_actual.department_code;

CREATE INDEX IF NOT EXISTS bi_mv_planificacion_kpi_idx0 ON bi_mv_planificacion_kpi (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_planificacion_kpi_idx1 ON bi_mv_planificacion_kpi (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_planificacion_kpi_idx2 ON bi_mv_planificacion_kpi (tipo_label);

CREATE VIEW bi_v_planificacion_kpi AS SELECT * FROM bi_mv_planificacion_kpi;

COMMENT ON VIEW bi_v_planificacion_kpi IS
  'KPIs Objetivos (solo filas P) / Plan por dept×tipo; filtro Planificado/Real vía tipo_label. (materializada: bi_mv_planificacion_kpi; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_planificacion_kpi IS
  'Snapshot de bi_v_planificacion_kpi; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_evolucion_mensual  ←  wrapper sobre bi_mv_evolucion_mensual
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_evolucion_mensual AS
SELECT
    f.empresa,
    f.year,
    f.month,
    f.ano_mes,
    f.codigo_unico_departamento,
    f.departamento::text AS department_code,
    d.department_name,
    f.tipo,
    CASE f.tipo
        WHEN 'P' THEN 'Planificado'
        WHEN 'R' THEN 'Real'
        ELSE COALESCE(f.tipo::text, '')
    END AS tipo_label,
    f.job,
    f.encabezado AS proyecto,
    SUM(f.facturado) AS facturacion,
    SUM(f.coste) AS coste,
    SUM(f.facturado - f.coste) AS beneficio,
    CASE
        WHEN SUM(f.facturado) > 0
            THEN (SUM(f.facturado) - SUM(f.coste)) / SUM(f.facturado) * 100
    END AS margen_pct
FROM v_se_facturacion f
LEFT JOIN mb_v_dim_departamento d
    ON d.company_name = f.empresa
   AND d.department_code = f.departamento
WHERE f.tipo IN ('P', 'R')
GROUP BY
    f.empresa,
    f.year,
    f.month,
    f.ano_mes,
    f.codigo_unico_departamento,
    f.departamento,
    d.department_name,
    f.tipo,
    f.job,
    f.encabezado;

CREATE INDEX IF NOT EXISTS bi_mv_evolucion_mensual_idx0 ON bi_mv_evolucion_mensual (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_evolucion_mensual_idx1 ON bi_mv_evolucion_mensual (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_evolucion_mensual_idx2 ON bi_mv_evolucion_mensual (tipo_label);
CREATE INDEX IF NOT EXISTS bi_mv_evolucion_mensual_idx3 ON bi_mv_evolucion_mensual (ano_mes);
CREATE INDEX IF NOT EXISTS bi_mv_evolucion_mensual_idx4 ON bi_mv_evolucion_mensual (proyecto);

CREATE VIEW bi_v_evolucion_mensual AS SELECT * FROM bi_mv_evolucion_mensual;

COMMENT ON VIEW bi_v_evolucion_mensual IS
  'Evolución mensual facturación/coste/margen por tipo P/R y proyecto. Fuente filtros Año/Empresa/Dept/Tipo/Proyecto. (materializada: bi_mv_evolucion_mensual; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_evolucion_mensual IS
  'Snapshot de bi_v_evolucion_mensual; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_facturacion_probabilidad  ←  wrapper sobre bi_mv_facturacion_probabilidad
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_facturacion_probabilidad AS
SELECT
    f.empresa,
    f.year,
    f.departamento::text AS department_code,
    d.department_name,
    f.job,
    f.encabezado AS proyecto,
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
    f.job,
    f.encabezado,
    CASE
        WHEN COALESCE(f.probability, 0) = 0 THEN 100::numeric
        ELSE COALESCE(f.probability, 0)
    END;

CREATE INDEX IF NOT EXISTS bi_mv_facturacion_probabilidad_idx0 ON bi_mv_facturacion_probabilidad (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_facturacion_probabilidad_idx1 ON bi_mv_facturacion_probabilidad (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_facturacion_probabilidad_idx2 ON bi_mv_facturacion_probabilidad (probabilidad);

CREATE VIEW bi_v_facturacion_probabilidad AS SELECT * FROM bi_mv_facturacion_probabilidad;

COMMENT ON VIEW bi_v_facturacion_probabilidad IS
  'Facturación P+R por probabilidad y proyecto (0→100 como PBI). Panel Resumen. (materializada: bi_mv_facturacion_probabilidad; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_facturacion_probabilidad IS
  'Snapshot de bi_v_facturacion_probabilidad; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_resumen_proyectos  ←  wrapper sobre bi_mv_resumen_proyectos
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_resumen_proyectos AS
SELECT
    f.empresa,
    f.year,
    f.departamento AS department_code,
    d.department_name,
    f.tipo,
    CASE f.tipo
        WHEN 'P' THEN 'Planificado'
        WHEN 'R' THEN 'Real'
        ELSE COALESCE(f.tipo::text, '')
    END AS tipo_label,
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

CREATE INDEX IF NOT EXISTS bi_mv_resumen_proyectos_idx0 ON bi_mv_resumen_proyectos (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_resumen_proyectos_idx1 ON bi_mv_resumen_proyectos (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_resumen_proyectos_idx2 ON bi_mv_resumen_proyectos (tipo_label);
CREATE INDEX IF NOT EXISTS bi_mv_resumen_proyectos_idx3 ON bi_mv_resumen_proyectos (proyecto);

CREATE VIEW bi_v_resumen_proyectos AS SELECT * FROM bi_mv_resumen_proyectos;

COMMENT ON VIEW bi_v_resumen_proyectos IS
  'Resumen Proyectos PBI: Operational + Completed/Open/Planning; excluye filas 0/0. (materializada: bi_mv_resumen_proyectos; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_resumen_proyectos IS
  'Snapshot de bi_v_resumen_proyectos; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_unidad  ←  wrapper sobre bi_mv_unidad
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_unidad AS
SELECT
    c.empresa,
    c.year,
    c.departamento AS department_code,
    d.department_name,
    c.tipo,
    CASE c.tipo
        WHEN 'P' THEN 'Planificado'
        WHEN 'R' THEN 'Real'
        ELSE COALESCE(c.tipo::text, '')
    END AS tipo_label,
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

CREATE INDEX IF NOT EXISTS bi_mv_unidad_idx0 ON bi_mv_unidad (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_unidad_idx1 ON bi_mv_unidad (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_unidad_idx2 ON bi_mv_unidad (tipo_label);
CREATE INDEX IF NOT EXISTS bi_mv_unidad_idx3 ON bi_mv_unidad (concepto_analitico);

CREATE VIEW bi_v_unidad AS SELECT * FROM bi_mv_unidad;

COMMENT ON VIEW bi_v_unidad IS
  'Unidad/Gastos PBI: coste por concepto×mes; tipo_proyecto=Structure fijo. (materializada: bi_mv_unidad; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_unidad IS
  'Snapshot de bi_v_unidad; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_facturacion  ←  wrapper sobre bi_mv_facturacion
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_facturacion AS
SELECT
    f.empresa,
    f.year,
    f.departamento AS department_code,
    d.department_name,
    f.tipo,
    CASE f.tipo
        WHEN 'P' THEN 'Planificado'
        WHEN 'R' THEN 'Real'
        ELSE COALESCE(f.tipo::text, '')
    END AS tipo_label,
    f.tipo_proyecto,
    f.estado,
    f.job,
    f.encabezado AS proyecto,
    SUM(f.facturado) FILTER (WHERE f.month = 1) AS m01,
    SUM(f.facturado) FILTER (WHERE f.month = 2) AS m02,
    SUM(f.facturado) FILTER (WHERE f.month = 3) AS m03,
    SUM(f.facturado) FILTER (WHERE f.month = 4) AS m04,
    SUM(f.facturado) FILTER (WHERE f.month = 5) AS m05,
    SUM(f.facturado) FILTER (WHERE f.month = 6) AS m06,
    SUM(f.facturado) FILTER (WHERE f.month = 7) AS m07,
    SUM(f.facturado) FILTER (WHERE f.month = 8) AS m08,
    SUM(f.facturado) FILTER (WHERE f.month = 9) AS m09,
    SUM(f.facturado) FILTER (WHERE f.month = 10) AS m10,
    SUM(f.facturado) FILTER (WHERE f.month = 11) AS m11,
    SUM(f.facturado) FILTER (WHERE f.month = 12) AS m12,
    SUM(f.facturado) AS total
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
HAVING ABS(SUM(f.facturado)) > 0.0001;

CREATE INDEX IF NOT EXISTS bi_mv_facturacion_idx0 ON bi_mv_facturacion (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_facturacion_idx1 ON bi_mv_facturacion (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_facturacion_idx2 ON bi_mv_facturacion (tipo_label);
CREATE INDEX IF NOT EXISTS bi_mv_facturacion_idx3 ON bi_mv_facturacion (proyecto);

CREATE VIEW bi_v_facturacion AS SELECT * FROM bi_mv_facturacion;

COMMENT ON VIEW bi_v_facturacion IS
  'Facturación PBI: Operational + Completed/Open/Planning; pivot facturado×mes; total>0. (materializada: bi_mv_facturacion; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_facturacion IS
  'Snapshot de bi_v_facturacion; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_gastos  ←  wrapper sobre bi_mv_gastos
-- Pestaña Gastos PBI: Encabezado × meses (coste); mismos filtros que Facturación.
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_gastos AS
SELECT
    c.empresa,
    c.year,
    c.departamento AS department_code,
    d.department_name,
    c.tipo,
    CASE c.tipo
        WHEN 'P' THEN 'Planificado'
        WHEN 'R' THEN 'Real'
        ELSE COALESCE(c.tipo::text, '')
    END AS tipo_label,
    c.tipo_proyecto,
    c.estado,
    c.job,
    (c.job::text || ' --- '::text) || "left"(COALESCE(c.descripcion, ''::character varying)::text, 36) AS proyecto,
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
WHERE c.tipo IN ('P', 'R')
  AND c.tipo_proyecto = 'Operational'
  AND COALESCE(c.estado, '') IN ('Completed', 'Open', 'Planning')
  -- PBI Gastos / Facturación: no sumar Mano de Obra Resource (solo G/L, Item, …)
  AND COALESCE(c.type_line, '') <> 'Resource'
GROUP BY
    c.empresa,
    c.year,
    c.departamento,
    d.department_name,
    c.tipo,
    c.tipo_proyecto,
    c.estado,
    c.job,
    c.descripcion
HAVING ABS(SUM(c.coste)) > 0.0001;

CREATE INDEX IF NOT EXISTS bi_mv_gastos_idx0 ON bi_mv_gastos (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_gastos_idx1 ON bi_mv_gastos (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_gastos_idx2 ON bi_mv_gastos (tipo_label);
CREATE INDEX IF NOT EXISTS bi_mv_gastos_idx3 ON bi_mv_gastos (proyecto);

CREATE VIEW bi_v_gastos AS SELECT * FROM bi_mv_gastos;

COMMENT ON VIEW bi_v_gastos IS
  'Gastos PBI: Operational + Completed/Open/Planning; excl. type_line Resource; pivot coste×mes Encabezado; total>0. (materializada: bi_mv_gastos; REFRESH tras sync 004).';
COMMENT ON MATERIALIZED VIEW bi_mv_gastos IS
  'Snapshot de bi_v_gastos; refrescar tras sync BC→Analytics.';

-- -----------------------------------------------------------------------------
-- bi_v_mano_obra  ←  wrapper sobre bi_mv_mano_obra
-- Pestaña Mano de Obra PBI: jerarquía Proyecto → Recurso.
-- nivel=0 → fila padre (proyecto agregado, sort_key = 'proyecto|0|')
-- nivel=1 → fila hijo  (recurso individual,  sort_key = 'proyecto|1|recurso')
-- AG Grid ordena por sort_key; JS aplica solo CSS (sin tocar rowData → rápido).
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW bi_mv_mano_obra AS
-- ── Filas HIJO (recurso individual) ──────────────────────────────────────────
WITH base AS (
  SELECT
      c.empresa,
      c.year,
      c.departamento AS department_code,
      d.department_name,
      c.tipo,
      CASE c.tipo WHEN 'P' THEN 'Planificado' WHEN 'R' THEN 'Real'
                  ELSE COALESCE(c.tipo::text, '') END AS tipo_label,
      c.tipo_proyecto,
      c.estado,
      c.job,
      (c.job::text || ' --- ') || left(COALESCE(c.descripcion,''), 36) AS proyecto,
      COALESCE(NULLIF(TRIM(r.name),''), NULLIF(TRIM(c.nr),''), '(sin recurso)') AS recurso,
      SUM(c.coste) FILTER (WHERE c.month =  1) AS m01,
      SUM(c.coste) FILTER (WHERE c.month =  2) AS m02,
      SUM(c.coste) FILTER (WHERE c.month =  3) AS m03,
      SUM(c.coste) FILTER (WHERE c.month =  4) AS m04,
      SUM(c.coste) FILTER (WHERE c.month =  5) AS m05,
      SUM(c.coste) FILTER (WHERE c.month =  6) AS m06,
      SUM(c.coste) FILTER (WHERE c.month =  7) AS m07,
      SUM(c.coste) FILTER (WHERE c.month =  8) AS m08,
      SUM(c.coste) FILTER (WHERE c.month =  9) AS m09,
      SUM(c.coste) FILTER (WHERE c.month = 10) AS m10,
      SUM(c.coste) FILTER (WHERE c.month = 11) AS m11,
      SUM(c.coste) FILTER (WHERE c.month = 12) AS m12,
      SUM(c.coste) AS total
  FROM v_se_coste c
  LEFT JOIN mb_v_dim_departamento d
      ON d.company_name = c.empresa AND d.department_code = c.departamento
  LEFT JOIN bc_resource r
      ON r.code = c.nr AND r.company_name = c.empresa
  WHERE c.tipo IN ('P','R')
    AND c.tipo_proyecto = 'Operational'
    AND COALESCE(c.estado,'') IN ('Completed','Open','Planning')
    AND COALESCE(c.type_line,'') = 'Resource'
    AND (COALESCE(TRIM(c.descripcion_ca),'') = '' OR c.descripcion_ca LIKE 'Mano de Obra%')
  GROUP BY c.empresa, c.year, c.departamento, d.department_name,
           c.tipo, c.tipo_proyecto, c.estado, c.job, c.descripcion, c.nr, r.name
  HAVING ABS(SUM(c.coste)) > 0.0001
)
-- Filas hijo (nivel=1): nombre = recurso indentado por CSS
SELECT
    empresa, year, department_code, department_name,
    tipo, tipo_label, tipo_proyecto, estado,
    1                        AS nivel,
    proyecto                 AS proyecto,
    recurso                  AS nombre,
    proyecto || '|1|' || recurso AS sort_key,
    m01, m02, m03, m04, m05, m06, m07, m08, m09, m10, m11, m12, total
FROM base

UNION ALL

-- Filas padre (nivel=0): nombre = proyecto; métricas = SUM de hijos
SELECT
    empresa, year, department_code, department_name,
    tipo, tipo_label, tipo_proyecto, estado,
    0                        AS nivel,
    proyecto                 AS proyecto,
    proyecto                 AS nombre,
    proyecto || '|0|'        AS sort_key,
    SUM(m01), SUM(m02), SUM(m03), SUM(m04), SUM(m05), SUM(m06),
    SUM(m07), SUM(m08), SUM(m09), SUM(m10), SUM(m11), SUM(m12),
    SUM(total)
FROM base
GROUP BY empresa, year, department_code, department_name,
         tipo, tipo_label, tipo_proyecto, estado, proyecto;

CREATE INDEX IF NOT EXISTS bi_mv_mano_obra_idx0 ON bi_mv_mano_obra (empresa, year);
CREATE INDEX IF NOT EXISTS bi_mv_mano_obra_idx1 ON bi_mv_mano_obra (department_code);
CREATE INDEX IF NOT EXISTS bi_mv_mano_obra_idx2 ON bi_mv_mano_obra (tipo_label);
CREATE INDEX IF NOT EXISTS bi_mv_mano_obra_idx3 ON bi_mv_mano_obra (sort_key);

CREATE VIEW bi_v_mano_obra AS SELECT * FROM bi_mv_mano_obra;

COMMENT ON VIEW bi_v_mano_obra IS
  'Mano de Obra: nivel 0=proyecto (padre), 1=recurso (hijo). Ordenar por sort_key. CSS en tail_js aplica sangrado; sin manipulación de rowData → sin bucles.';
COMMENT ON MATERIALIZED VIEW bi_mv_mano_obra IS
  'Snapshot bi_v_mano_obra (nivel 0+1); refrescar tras sync BC→Analytics.';

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

-- Fin capa BI (MVs + wrappers).
