-- ============================================================================
-- ANALYTICS DB ONLY (VM 100 prod / VM 102 dev / VM 103 testing)
-- Views Seguimiento Económico PS — réplica Superset del informe Power BI
-- Spec: superset-analytics/docs/seguimiento-economico/
-- ============================================================================

-- Helpers: probabilidad BC (0 = firmado → 100%)
CREATE OR REPLACE FUNCTION public.se_prob_pct(p_probability numeric)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN COALESCE(p_probability, 0) = 0 THEN 100 ELSE p_probability::integer END;
$$;

CREATE OR REPLACE FUNCTION public.se_weight_amount(p_probability numeric, p_amount numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_amount, 0) = 0 THEN 0
    WHEN COALESCE(p_probability, 0) = 0 THEN p_amount
    ELSE p_amount * p_probability / 100
  END;
$$;

COMMENT ON FUNCTION public.se_prob_pct IS
  'PBI Seguimiento Económico: probability=0 significa 100% (proyecto firmado).';

-- ---------------------------------------------------------------------------
-- Dimensiones (Empresas, Años, Departamentos)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_se_dim_empresas AS
SELECT
  company_name AS display_name
FROM public.companys;

COMMENT ON VIEW public.v_se_dim_empresas IS
  'PBI Empresas — Display_Name';

CREATE OR REPLACE VIEW public.v_se_dim_departamentos AS
SELECT
  d.company_name,
  d.code AS departamento,
  d.name AS descripcion,
  d.company_name || ':' || d.code AS codigo_unico_departamento
FROM public.bc_department d;

COMMENT ON VIEW public.v_se_dim_departamentos IS
  'PBI Departamentos — CodigoUnicoDepartamento = Empresa:departamento';

CREATE OR REPLACE VIEW public.v_se_dim_anos AS
SELECT DISTINCT
  f.company_name || ':' || f.year::text AS empresa_ano,
  f.company_name,
  f.year AS ano
FROM (
  SELECT company_name, year FROM public.bc_job_planning_line WHERE year IS NOT NULL
  UNION
  SELECT company_name, ps_year AS year FROM public.bc_ps_year WHERE ps_year IS NOT NULL
) f;

COMMENT ON VIEW public.v_se_dim_anos IS
  'PBI Años — EmpresaAño';

-- ---------------------------------------------------------------------------
-- Lineas Planificacion (Tipo P) — planificacionMes
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_se_lineas_planificacion AS
SELECT
  p.company_name AS empresa,
  p.job_no AS job,
  p.year,
  p.month,
  p.invoice,
  p.cost,
  p.line_no AS nr,
  p.type_line,
  p.quantity,
  p.line_type,
  p.departamento,
  COALESCE(p.description, j.description) AS descripcion,
  p.status AS estado,
  p.tipo_proyecto,
  p.probability,
  p.budget_date_year,
  p.budget_date_month,
  p.month_closing_status AS status1,
  p.concepto_analitico_descripcion AS descripcion_ca,
  'P'::text AS tipo,
  public.se_weight_amount(p.probability, p.invoice) AS facturado,
  public.se_prob_pct(p.probability) AS prob_pct,
  public.se_weight_amount(p.probability, p.cost) AS coste,
  public.se_weight_amount(p.probability, p.quantity) AS cantidad,
  p.company_name || ':' || p.departamento AS codigo_unico_departamento,
  make_date(p.year, p.month, 1) AS fecha_calculada,
  p.company_name || ':' || p.year::text AS empresa_ano,
  p.company_name || ':' || COALESCE(p.line_no, '') AS empresa_recurso
FROM public.bc_job_planning_line p
LEFT JOIN public.bc_job j
  ON j.company_name = p.company_name AND j.no = p.job_no
WHERE p.job_no IS NOT NULL
  AND p.job_no NOT LIKE 'PP%'
  AND p.status IN ('Open', 'Planning')
  AND public.se_pass_budget_filter(
    p.year, p.month, p.budget_date_year, p.budget_date_month
  );

COMMENT ON VIEW public.v_se_lineas_planificacion IS
  'PBI Lineas PLanificacion — Tipo P. Fuente bc_job_planning_line.';

-- ---------------------------------------------------------------------------
-- Lineas Movimientos (Tipo R) — movimientosProyectosMes
-- Requiere month/year en ledger (Fase 2: API MovimientosProyectosMes en workflow 004)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_se_lineas_movimientos AS
SELECT
  e.company_name AS empresa,
  e.job_no AS job,
  COALESCE(
    e.year,
    EXTRACT(YEAR FROM COALESCE(e.timesheet_date, e.document_date))::integer
  ) AS year,
  COALESCE(
    e.month,
    EXTRACT(MONTH FROM COALESCE(e.timesheet_date, e.document_date))::integer
  ) AS month,
  CASE
    WHEN COALESCE(e.concepto_analitico_descripcion, '') = 'Kilometraje' THEN 0
    WHEN COALESCE(e.origen, '') ILIKE '%resource%' THEN 0
    ELSE COALESCE(-e.total_price, -e.line_price, 0)
  END AS invoice,
  e.total_cost AS cost,
  e.no AS nr,
  NULL::varchar(50) AS type_line,
  e.quantity,
  NULL::varchar(50) AS line_type,
  COALESCE(e.global_dimension1_code, j.departamento) AS departamento,
  COALESCE(e.description, j.description) AS descripcion,
  j.status AS estado,
  j.tipo_proyecto,
  j.probability,
  NULL::integer AS budget_date_year,
  NULL::integer AS budget_date_month,
  NULL::varchar(20) AS status1,
  e.concepto_analitico_descripcion AS descripcion_ca,
  'R'::text AS tipo,
  public.se_weight_amount(j.probability, CASE
    WHEN COALESCE(e.concepto_analitico_descripcion, '') = 'Kilometraje' THEN 0
    WHEN COALESCE(e.origen, '') ILIKE '%resource%' THEN 0
    ELSE COALESCE(-e.total_price, -e.line_price, 0)
  END) AS facturado,
  public.se_prob_pct(j.probability) AS prob_pct,
  public.se_weight_amount(j.probability, e.total_cost) AS coste,
  public.se_weight_amount(j.probability, e.quantity) AS cantidad,
  e.company_name || ':' || COALESCE(e.global_dimension1_code, j.departamento, '') AS codigo_unico_departamento,
  make_date(
    COALESCE(e.year, EXTRACT(YEAR FROM COALESCE(e.timesheet_date, e.document_date))::integer),
    COALESCE(e.month, EXTRACT(MONTH FROM COALESCE(e.timesheet_date, e.document_date))::integer),
    1
  ) AS fecha_calculada,
  e.company_name || ':' || COALESCE(
    e.year::text,
    EXTRACT(YEAR FROM COALESCE(e.timesheet_date, e.document_date))::text
  ) AS empresa_ano,
  e.company_name || ':' || COALESCE(e.no, '') AS empresa_recurso
FROM public.bc_job_ledger_entry e
LEFT JOIN public.bc_job j
  ON j.company_name = e.company_name AND j.no = e.job_no
WHERE e.job_no IS NOT NULL
  AND e.job_no NOT LIKE 'PP%'
  AND (
    e.year IS NOT NULL
    OR e.timesheet_date IS NOT NULL
    OR e.document_date IS NOT NULL
  );

COMMENT ON VIEW public.v_se_lineas_movimientos IS
  'PBI Lineas Proyectos — Tipo R. Parcial hasta 004 sincronice MovimientosProyectosMes.';

-- ---------------------------------------------------------------------------
-- Facturacion — UNION (expediente + meses cerrados en Fase 2)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_se_facturacion AS
SELECT
  empresa,
  job,
  year,
  month,
  invoice,
  cost,
  nr,
  type_line,
  quantity,
  line_type,
  departamento,
  descripcion,
  estado,
  tipo_proyecto,
  probability,
  descripcion_ca,
  tipo,
  facturado,
  prob_pct AS pct,
  coste,
  cantidad,
  codigo_unico_departamento,
  fecha_calculada,
  empresa_ano,
  empresa_recurso,
  job || ' --- ' || LEFT(COALESCE(descripcion, ''), 36) AS encabezado,
  LPAD(month::text, 2, '0') AS mes_tex,
  LPAD(month::text, 2, '0') || '/' || year::text AS ano_mes,
  CASE WHEN COALESCE(facturado, 0) <> 0 THEN facturado END AS facturacion_no_cero,
  facturado - coste AS neto,
  CASE WHEN COALESCE(cantidad, 0) <> 0 THEN coste / cantidad END AS coste_medio
FROM public.v_se_lineas_planificacion
WHERE year IS NOT NULL AND month IS NOT NULL

UNION ALL

SELECT
  empresa,
  job,
  year,
  month,
  invoice,
  cost,
  nr,
  type_line,
  quantity,
  line_type,
  departamento,
  descripcion,
  estado,
  tipo_proyecto,
  probability,
  descripcion_ca,
  tipo,
  facturado,
  prob_pct AS pct,
  coste,
  cantidad,
  codigo_unico_departamento,
  fecha_calculada,
  empresa_ano,
  empresa_recurso,
  job || ' --- ' || LEFT(COALESCE(descripcion, ''), 36) AS encabezado,
  LPAD(month::text, 2, '0') AS mes_tex,
  LPAD(month::text, 2, '0') || '/' || year::text AS ano_mes,
  CASE WHEN COALESCE(facturado, 0) <> 0 THEN facturado END AS facturacion_no_cero,
  facturado - coste AS neto,
  CASE WHEN COALESCE(cantidad, 0) <> 0 THEN coste / cantidad END AS coste_medio
FROM public.v_se_lineas_movimientos
WHERE year IS NOT NULL AND month IS NOT NULL;

COMMENT ON VIEW public.v_se_facturacion IS
  'PBI Facturacion — UNION planificación (P) + movimientos (R). Añadir expediente/meses cerrados en Fase 2.';

-- ---------------------------------------------------------------------------
-- FacturacionRecursos — mano de obra planificada
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_se_facturacion_recursos AS
SELECT f.*
FROM public.v_se_facturacion f
WHERE COALESCE(f.type_line, 'Resource') = 'Resource'
  AND COALESCE(f.line_type, '') <> 'Billable'
  AND COALESCE(f.descripcion_ca, '') <> 'Mano de Obra -Servicio-Vacaciones-Extra';

COMMENT ON VIEW public.v_se_facturacion_recursos IS
  'PBI FacturacionRecursos — solo líneas Resource no Billable.';

-- ---------------------------------------------------------------------------
-- Métricas agregadas (equivalente medidas DAX base)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_se_resumen_mensual AS
SELECT
  empresa,
  year,
  month,
  ano_mes,
  fecha_calculada,
  codigo_unico_departamento,
  tipo,
  SUM(facturado) AS total_venta,
  SUM(coste) AS total_gasto,
  SUM(facturacion_no_cero) AS total_facturacion_no_cero,
  CASE
    WHEN SUM(facturado) = 0 THEN NULL
    ELSE (SUM(facturado) - SUM(coste)) / SUM(facturado)
  END AS margen_pct,
  SUM(facturado) - SUM(coste) AS margen_eur
FROM public.v_se_facturacion
GROUP BY
  empresa, year, month, ano_mes, fecha_calculada,
  codigo_unico_departamento, tipo;

COMMENT ON VIEW public.v_se_resumen_mensual IS
  'Agregación mensual — base para KPIs Margen%, cards y pivots Superset.';
