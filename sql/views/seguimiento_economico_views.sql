-- ============================================================================
-- ANALYTICS DB ONLY (VM 100 / 102 / 103)
-- Vistas canónicas Seguimiento Económico (réplica PBI → Superset)
--
-- ⚠️  FUENTE DE VERDAD: este archivo en superset-analytics.
--     Cambios deben validarse contra PBI y aplicarse de forma controlada
--     en el entorno de Analytics antes de promoverlos.
--
-- Regenerado: 2026-07-23 desde pg_get_viewdef / pg_get_functiondef
-- Dashboard Superset (capa bi_v_*): scripts/sql/bi_dashboard_planificacion_views.sql
-- ============================================================================
-- ---------------------------------------------------------------------------
-- Function: se_prob_pct
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.se_prob_pct(p_probability numeric)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN COALESCE(p_probability, 0) = 0 THEN 100 ELSE p_probability::integer END;
$function$;
COMMENT ON FUNCTION public.se_prob_pct(numeric) IS
  'PBI Seguimiento Económico: probability=0 significa 100% (proyecto firmado).';

-- ---------------------------------------------------------------------------
-- Function: se_weight_amount
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.se_weight_amount(p_probability numeric, p_amount numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN COALESCE(p_amount, 0) = 0 THEN 0
    WHEN COALESCE(p_probability, 0) = 0 THEN p_amount
    ELSE p_amount * p_probability / 100
  END;
$function$;

-- ---------------------------------------------------------------------------
-- Function: se_pass_budget_filter
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.se_pass_budget_filter(p_year integer, p_month integer, p_budget_year integer, p_budget_month integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT
    COALESCE(p_budget_year, 0) = 0
    OR p_year < p_budget_year
    OR (p_year = p_budget_year AND p_month <= COALESCE(p_budget_month, 12));
$function$;
COMMENT ON FUNCTION public.se_pass_budget_filter(integer, integer, integer, integer) IS
  'PBI budget date: incluye líneas con year<budget_year o (year=budget_year y month<=budget_month).';

-- ---------------------------------------------------------------------------
-- View: v_se_dim_empresas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_dim_empresas AS
 SELECT DISTINCT j.company_name AS display_name
   FROM bc_job j
  WHERE j.company_name IS NOT NULL AND btrim(j.company_name) <> ''::text
  ORDER BY j.company_name;
COMMENT ON VIEW public.v_se_dim_empresas IS 'PBI Empresas — Display_Name (desde bc_job; sin tabla legacy companys)';

-- ---------------------------------------------------------------------------
-- View: v_se_dim_departamentos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_dim_departamentos AS
 SELECT d.company_name,
    d.code AS departamento,
    d.name AS descripcion,
    (d.company_name || ':'::text) || d.code::text AS codigo_unico_departamento
   FROM bc_department d;
COMMENT ON VIEW public.v_se_dim_departamentos IS 'PBI Departamentos — CodigoUnicoDepartamento = Empresa:departamento';

-- ---------------------------------------------------------------------------
-- View: v_se_dim_anos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_dim_anos AS
 SELECT DISTINCT (f.company_name || ':'::text) || f.year::text AS empresa_ano,
    f.company_name,
    f.year AS ano
   FROM ( SELECT bc_job_planning_line.company_name,
            bc_job_planning_line.year
           FROM bc_job_planning_line
          WHERE bc_job_planning_line.year IS NOT NULL
        UNION
         SELECT bc_ps_year.company_name,
            bc_ps_year.ps_year AS year
           FROM bc_ps_year
          WHERE bc_ps_year.ps_year IS NOT NULL) f;
COMMENT ON VIEW public.v_se_dim_anos IS 'PBI Años — EmpresaAño';

-- ---------------------------------------------------------------------------
-- View: v_se_lineas_planificacion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_lineas_planificacion AS
 WITH src AS (
         SELECT p.company_name AS empresa,
            p.job_no AS job,
            p.year,
            p.month,
            p.invoice,
            p.cost,
            p.line_no AS nr,
            p.type_line,
            p.quantity,
            p.line_type,
            COALESCE(NULLIF(btrim(p.departamento::text), ''::text), NULLIF(btrim(j.departamento::text), ''::text))::character varying(20) AS departamento,
            COALESCE(p.description, j.description) AS descripcion,
            p.status AS estado,
            p.tipo_proyecto,
            p.probability,
            p.do_not_consolidate,
            p.budget_date_year,
            p.budget_date_month,
            p.month_closing_status AS status1,
            p.concepto_analitico_descripcion AS descripcion_ca
           FROM bc_job_planning_line p
             LEFT JOIN bc_job j ON j.company_name = p.company_name AND j.no::text = p.job_no::text
          WHERE p.job_no IS NOT NULL AND btrim(p.job_no::text) <> ''::text AND p.job_no::text !~~ 'PP%'::text AND p.job_no::text !~~ 'PY%'::text AND (p.status::text = ANY (ARRAY['Open'::text, 'Planning'::text])) AND NOT (EXISTS ( SELECT 1
                   FROM bc_job_ledger_entry_month m
                  WHERE m.company_name = p.company_name AND m.job_no::text = p.job_no::text AND m.year = p.year AND m.month = p.month AND m.concepto_analitico_descripcion::text = 'Ingresos'::text AND m.invoice <> 0::numeric))
        ), dedup AS (
         SELECT DISTINCT ON (s.job, s.year, s.month, s.invoice, s.cost, s.nr, s.descripcion_ca) s.empresa,
            s.job,
            s.year,
            s.month,
            s.invoice,
            s.cost,
            s.nr,
            s.type_line,
            s.quantity,
            s.line_type,
            s.departamento,
            s.descripcion,
            s.estado,
            s.tipo_proyecto,
            s.probability,
            s.do_not_consolidate,
            s.budget_date_year,
            s.budget_date_month,
            s.status1,
            s.descripcion_ca
           FROM src s
          ORDER BY s.job, s.year, s.month, s.invoice, s.cost, s.nr, s.descripcion_ca
        )
 SELECT d.empresa,
    d.job,
    d.year,
    d.month,
    d.invoice,
    d.cost,
    d.nr,
    d.type_line,
    d.quantity,
    d.line_type,
    d.departamento,
    d.descripcion,
    d.estado,
    d.tipo_proyecto,
    d.probability,
    d.budget_date_year,
    d.budget_date_month,
    d.status1,
    d.descripcion_ca,
    'P'::text AS tipo,
    se_weight_amount(d.probability, d.invoice) AS facturado,
    se_prob_pct(d.probability) AS prob_pct,
    se_weight_amount(d.probability, d.cost) AS coste,
    se_weight_amount(d.probability, d.quantity) AS cantidad,
    (d.empresa || ':'::text) || COALESCE(d.departamento, ''::character varying)::text AS codigo_unico_departamento,
    make_date(d.year, d.month, 1) AS fecha_calculada,
    (d.empresa || ':'::text) || d.year::text AS empresa_ano,
    (d.empresa || ':'::text) || COALESCE(d.nr, ''::character varying)::text AS empresa_recurso
   FROM dedup d;
COMMENT ON VIEW public.v_se_lineas_planificacion IS 'PBI Lineas Planificacion: filtro budget (year=budgetYear, month>=budgetMonth), Distinct(job,year,month,invoice,cost,nr,descripcionCA), Open/Planning.';

-- ---------------------------------------------------------------------------
-- View: v_se_lineas_movimientos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_lineas_movimientos AS
 WITH src AS (
         SELECT m.company_name AS empresa,
            m.job_no AS job,
            m.year,
            m.month,
            m.invoice,
            m.cost,
            m.nr,
            m.type_line,
            m.line_type,
            m.quantity,
            COALESCE(m.departamento, j.departamento) AS departamento,
            COALESCE(m.description, j.description) AS descripcion,
            COALESCE(m.status, j.status) AS estado,
            COALESCE(m.tipo_proyecto, j.tipo_proyecto) AS tipo_proyecto,
            COALESCE(m.probability, j.probability) AS probability,
            m.do_not_consolidate,
            m.budget_date_year,
            m.budget_date_month,
            m.month_closing_status AS status1,
            m.concepto_analitico_descripcion AS descripcion_ca,
            m.document_no,
            m.document_date,
            m.timesheet_date,
                CASE
                    WHEN m.concepto_analitico_descripcion::text = 'Kilometraje'::text THEN 0::numeric
                    WHEN m.type_line::text = 'Resource'::text THEN 0::numeric
                    ELSE COALESCE(m.invoice, 0::numeric)
                END AS invoice_m
           FROM bc_job_ledger_entry_month m
             LEFT JOIN bc_job j ON j.company_name = m.company_name AND j.no::text = m.job_no::text
          WHERE m.job_no IS NOT NULL
        )
 SELECT s.empresa,
    s.job,
    s.year,
    s.month,
    s.invoice_m::numeric(15,5) AS invoice,
    s.cost,
    s.nr,
    s.type_line,
    s.quantity,
    s.line_type,
    s.departamento,
    s.descripcion,
    s.estado,
    s.tipo_proyecto,
    s.probability,
    s.budget_date_year,
    s.budget_date_month,
    s.status1,
    s.descripcion_ca,
    'R'::text AS tipo,
    s.invoice_m AS facturado,
    se_prob_pct(s.probability) AS prob_pct,
    s.cost::numeric AS coste,
    s.quantity::numeric AS cantidad,
    (s.empresa || ':'::text) || COALESCE(s.departamento, ''::character varying)::text AS codigo_unico_departamento,
        CASE
            WHEN s.timesheet_date IS NOT NULL AND EXTRACT(year FROM s.timesheet_date) > 1001::numeric THEN s.timesheet_date
            ELSE s.document_date
        END AS fecha_calculada,
    (s.empresa || ':'::text) || s.year::text AS empresa_ano,
    (s.empresa || ':'::text) || COALESCE(s.nr, ''::character varying)::text AS empresa_recurso
   FROM src s;
COMMENT ON VIEW public.v_se_lineas_movimientos IS 'Replica M de Power BI para movimientosProyectosMes: invoice ya transformado en sync (OData * -1); sin ABS.';

-- ---------------------------------------------------------------------------
-- View: v_se_lineas_expedientes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_lineas_expedientes AS
 WITH version_stats AS (
         SELECT p.company_name,
            p.budget_date_year AS byear,
            p.budget_date_month AS bmonth,
            count(*) AS n
           FROM bc_job_planning_line p
          WHERE (p.status::text = ANY (ARRAY['Open'::character varying, 'Planning'::character varying]::text[])) AND COALESCE(p.budget_date_year, 0) > 0 AND COALESCE(p.budget_date_month, 0) > 0
          GROUP BY p.company_name, p.budget_date_year, p.budget_date_month
        ), max_n AS (
         SELECT version_stats.company_name,
            max(version_stats.n) AS mx
           FROM version_stats
          GROUP BY version_stats.company_name
        ), plateau AS (
         SELECT v.company_name,
            v.byear,
            v.bmonth,
            v.n
           FROM version_stats v
             JOIN max_n m ON m.company_name = v.company_name AND v.n::numeric >= (m.mx::numeric * 0.85)
        ), vigente AS (
         SELECT DISTINCT ON (p.company_name) p.company_name,
            p.byear AS budget_date_year,
            p.bmonth AS budget_date_month
           FROM plateau p
          ORDER BY p.company_name, (abs(p.bmonth - EXTRACT(month FROM CURRENT_DATE)::integer) + abs(p.byear - EXTRACT(year FROM CURRENT_DATE)::integer) * 12), p.byear DESC, p.bmonth DESC
        ), src AS (
         SELECT e.company_name AS empresa,
            e.job_no AS job,
            e.year,
            e.month,
            e.invoice,
            COALESCE(NULLIF(btrim(e.departamento::text), ''::text), NULLIF(btrim(j.departamento::text), ''::text))::character varying(20) AS departamento,
            COALESCE(e.description, j.description) AS descripcion,
            COALESCE(e.status, j.status) AS estado,
            COALESCE(e.tipo_proyecto, j.tipo_proyecto) AS tipo_proyecto,
            COALESCE(e.probability, j.probability) AS probability,
            e.budget_date_year,
            e.budget_date_month,
            e.month_closing_status AS status1
           FROM bc_expediente_mes e
             JOIN vigente v ON v.company_name = e.company_name AND v.budget_date_year = e.budget_date_year AND v.budget_date_month = e.budget_date_month
             LEFT JOIN bc_job j ON j.company_name = e.company_name AND j.no::text = e.job_no::text
          WHERE e.job_no IS NOT NULL AND btrim(e.job_no::text) <> ''::text AND e.job_no::text !~~ 'PP%'::text AND e.job_no::text !~~ 'PY%'::text AND (COALESCE(e.budget_date_year, 0) = 0 OR e.year = e.budget_date_year AND e.month >= COALESCE(NULLIF(e.budget_date_month, 0), 1)) AND (COALESCE(e.month_closing_status, ''::character varying)::text <> ALL (ARRAY['Completed'::character varying, 'Lost'::character varying]::text[]))
        ), dedup AS (
         SELECT DISTINCT ON (s.empresa, s.job, s.year, s.month, s.invoice) s.empresa,
            s.job,
            s.year,
            s.month,
            s.invoice,
            s.departamento,
            s.descripcion,
            s.estado,
            s.tipo_proyecto,
            s.probability,
            s.budget_date_year,
            s.budget_date_month,
            s.status1
           FROM src s
          ORDER BY s.empresa, s.job, s.year, s.month, s.invoice
        )
 SELECT d.empresa,
    d.job,
    d.year,
    d.month,
    d.invoice,
    NULL::numeric(15,5) AS cost,
    NULL::character varying(20) AS nr,
    NULL::character varying(50) AS type_line,
    NULL::numeric(15,5) AS quantity,
    NULL::character varying(50) AS line_type,
    d.departamento,
    d.descripcion,
    d.estado,
    d.tipo_proyecto,
    d.probability,
    d.budget_date_year,
    d.budget_date_month,
    d.status1,
    NULL::character varying(100) AS descripcion_ca,
    'P'::text AS tipo,
    se_weight_amount(d.probability, d.invoice) AS facturado,
    se_prob_pct(d.probability) AS prob_pct,
    0::numeric(15,5) AS coste,
    0::numeric(15,5) AS cantidad,
    (d.empresa || ':'::text) || COALESCE(d.departamento, ''::character varying)::text AS codigo_unico_departamento,
    make_date(d.year, d.month, 1) AS fecha_calculada,
    (d.empresa || ':'::text) || d.year::text AS empresa_ano,
    d.empresa || ':'::text AS empresa_recurso
   FROM dedup d;
COMMENT ON VIEW public.v_se_lineas_expedientes IS 'PBI Lineas Expedientes: filtro budget M, Distinct(job,year,month,invoice), excluye Completed/Lost.';

-- ---------------------------------------------------------------------------
-- View: v_se_lineas_meses_cerrados
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_lineas_meses_cerrados AS
 SELECT c.company_name AS empresa,
    c.job_no AS job,
    c.year,
    c.month,
    NULL::numeric(15,5) AS invoice,
    0::numeric(15,5) AS cost,
    NULL::character varying(20) AS nr,
    'Resource'::character varying(50) AS type_line,
    NULL::numeric(15,5) AS quantity,
    NULL::character varying(50) AS line_type,
    j.departamento,
    j.description AS descripcion,
    j.status AS estado,
    j.tipo_proyecto,
    j.probability,
    NULL::integer AS budget_date_year,
    NULL::integer AS budget_date_month,
    NULL::character varying(20) AS status1,
    NULL::character varying(100) AS descripcion_ca,
    'R'::text AS tipo,
    0::numeric AS facturado,
    se_prob_pct(j.probability) AS prob_pct,
    0::numeric(15,5) AS coste,
    NULL::numeric(15,5) AS cantidad,
    (c.company_name || ':'::text) || COALESCE(j.departamento, ''::character varying)::text AS codigo_unico_departamento,
    make_date(c.year, c.month, 1) AS fecha_calculada,
    (c.company_name || ':'::text) || c.year::text AS empresa_ano,
    (c.company_name || ':'::text) || COALESCE(NULL::character varying, ''::character varying)::text AS empresa_recurso
   FROM bc_meses_cerrados c
     LEFT JOIN bc_job j ON j.company_name = c.company_name AND j.no::text = c.job_no::text
  WHERE c.job_no IS NOT NULL AND btrim(c.job_no::text) <> ''::text;
COMMENT ON VIEW public.v_se_lineas_meses_cerrados IS 'Replica M de PBI para mesesCerrados: marcador de cierre por job/mes, enriquecido con proyecto, sin importe/coste.';

-- ---------------------------------------------------------------------------
-- View: v_se_objectives
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_objectives AS
 SELECT o.company_name AS empresa,
    o.department_code AS departamento,
    o.year AS ano,
    o.cost_target,
    o.billing_target,
    o.margin_target,
    (o.company_name || ':'::text) || o.department_code::text AS codigo_unico_departamento,
    (o.company_name || ':'::text) || o.year::text AS empresa_ano,
        CASE
            WHEN COALESCE(o.billing_target, 0::numeric) = 0::numeric THEN NULL::numeric
            ELSE (o.billing_target - o.cost_target) / o.billing_target
        END AS margen_real_pct,
    o.billing_target - o.cost_target AS beneficio_eur
   FROM bc_objectives_by_department o;
COMMENT ON VIEW public.v_se_objectives IS 'PBI Objetivos — equivalente medidas MArgenReal% y Beneficio€.';

-- ---------------------------------------------------------------------------
-- View: v_se_historico_planificacion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_historico_planificacion AS
 SELECT h.company_name AS empresa,
    h.job_no AS job,
    h.year AS ano,
    h.month,
    h.closing_month_code,
    h.nr,
    h.type_line,
    h.line_type,
    h.invoice,
    h.cost,
    h.quantity,
    h.departamento,
    h.description AS descripcion,
    h.status AS estado,
    h.tipo_proyecto,
    h.probability,
    (h.company_name || ':'::text) || COALESCE(h.departamento, ''::character varying)::text AS codigo_unico_departamento,
    (h.company_name || ':'::text) || h.year::text AS empresa_ano,
    se_weight_amount(h.probability, h.invoice) AS facturado,
    se_weight_amount(h.probability, h.cost) AS coste,
        CASE
            WHEN se_weight_amount(h.probability, h.invoice) = 0::numeric THEN NULL::numeric
            ELSE (se_weight_amount(h.probability, h.invoice) - se_weight_amount(h.probability, h.cost)) / se_weight_amount(h.probability, h.invoice)
        END AS margen_pct_historico
   FROM bc_historico_planificacion_mes h;
COMMENT ON VIEW public.v_se_historico_planificacion IS 'PBI HistoricoPlanificacion — medida Margen%Historico.';

-- ---------------------------------------------------------------------------
-- View: v_se_facturacion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_facturacion AS
 WITH origen AS (
         SELECT p.empresa,
            p.job,
            p.year,
            p.month,
            p.invoice,
            p.cost,
            p.nr,
            p.type_line,
            p.quantity,
            p.line_type,
            p.departamento,
            p.descripcion,
            p.estado,
            p.tipo_proyecto,
            p.probability,
            p.descripcion_ca,
            p.tipo
           FROM v_se_lineas_planificacion p
          WHERE p.year IS NOT NULL AND p.month IS NOT NULL
        UNION ALL
         SELECT m.empresa,
            m.job,
            m.year,
            m.month,
            m.invoice,
            m.cost,
            m.nr,
            m.type_line,
            m.quantity,
            m.line_type,
            m.departamento,
            m.descripcion,
            m.estado,
            m.tipo_proyecto,
            m.probability,
            m.descripcion_ca,
            m.tipo
           FROM v_se_lineas_movimientos m
          WHERE m.year IS NOT NULL AND m.month IS NOT NULL
        UNION ALL
         SELECT e.empresa,
            e.job,
            e.year,
            e.month,
            e.invoice,
            e.cost,
            e.nr,
            e.type_line,
            e.quantity,
            e.line_type,
            e.departamento,
            e.descripcion,
            e.estado,
            e.tipo_proyecto,
            e.probability,
            e.descripcion_ca,
            e.tipo
           FROM v_se_lineas_expedientes e
          WHERE e.year IS NOT NULL AND e.month IS NOT NULL
        UNION ALL
         SELECT c.empresa,
            c.job,
            c.year,
            c.month,
            c.invoice,
            c.cost,
            c.nr,
            c.type_line,
            c.quantity,
            c.line_type,
            c.departamento,
            c.descripcion,
            c.estado,
            c.tipo_proyecto,
            c.probability,
            c.descripcion_ca,
            c.tipo
           FROM v_se_lineas_meses_cerrados c
          WHERE c.year IS NOT NULL AND c.month IS NOT NULL
        )
 SELECT o.empresa,
    o.job,
    o.year,
    o.month,
    COALESCE(o.invoice, 0::numeric)::numeric(15,5) AS invoice,
    COALESCE(o.cost, 0::numeric)::numeric(15,5) AS cost,
    o.nr,
    o.type_line,
    COALESCE(o.quantity, 0::numeric)::numeric(15,5) AS quantity,
    o.line_type,
    o.departamento,
    o.descripcion,
    o.estado,
    o.tipo_proyecto,
    COALESCE(o.probability, 0::numeric)::numeric(5,2) AS probability,
    o.descripcion_ca,
    o.tipo,
    se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.invoice, 0::numeric)) AS facturado,
    se_prob_pct(COALESCE(o.probability, 0::numeric)) AS pct,
    se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.cost, 0::numeric)) AS coste,
    se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.quantity, 0::numeric)) AS cantidad,
    (o.empresa || ':'::text) || COALESCE(o.departamento, ''::character varying)::text AS codigo_unico_departamento,
    make_date(o.year, o.month, 1) AS fecha_calculada,
    (o.empresa || ':'::text) || o.year::text AS empresa_ano,
    (o.empresa || ':'::text) || COALESCE(o.nr, ''::character varying)::text AS empresa_recurso,
    (o.job::text || ' --- '::text) || "left"(COALESCE(o.descripcion, ''::character varying)::text, 36) AS encabezado,
    lpad(o.month::text, 2, '0'::text) AS mes_tex,
    (lpad(o.month::text, 2, '0'::text) || '/'::text) || o.year::text AS ano_mes,
        CASE
            WHEN COALESCE(se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.invoice, 0::numeric)), 0::numeric) <> 0::numeric THEN se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.invoice, 0::numeric))
            ELSE NULL::numeric
        END AS facturacion_no_cero,
    se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.invoice, 0::numeric)) - se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.cost, 0::numeric)) AS neto,
        CASE
            WHEN COALESCE(se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.quantity, 0::numeric)), 0::numeric) <> 0::numeric THEN se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.cost, 0::numeric)) / se_weight_amount(COALESCE(o.probability, 0::numeric), COALESCE(o.quantity, 0::numeric))
            ELSE NULL::numeric
        END AS coste_medio
   FROM origen o;
COMMENT ON VIEW public.v_se_facturacion IS 'Replica de la tabla interna Facturacion de PBI combinando 4 fuentes y ponderando por probabilidad.';

-- ---------------------------------------------------------------------------
-- View: v_se_facturacion_recursos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_facturacion_recursos AS
 SELECT f.empresa,
    f.job,
    f.year,
    f.month,
    f.invoice,
    f.cost,
    f.nr,
    f.type_line,
    f.quantity,
    f.line_type,
    f.departamento,
    f.descripcion,
    f.estado,
    f.tipo_proyecto,
    f.probability,
    f.descripcion_ca,
    f.tipo,
    f.facturado,
    f.pct,
    f.coste,
    f.cantidad,
    f.codigo_unico_departamento,
    f.fecha_calculada,
    f.empresa_ano,
    f.empresa_recurso,
    f.encabezado,
    f.mes_tex,
    f.ano_mes,
    f.facturacion_no_cero,
    f.neto,
    f.coste_medio
   FROM v_se_facturacion f
  WHERE COALESCE(f.type_line, 'Resource'::character varying)::text = 'Resource'::text AND COALESCE(f.line_type, ''::character varying)::text <> 'Billable'::text AND COALESCE(f.descripcion_ca, ''::character varying)::text <> 'Mano de Obra -Servicio-Vacaciones-Extra'::text;
COMMENT ON VIEW public.v_se_facturacion_recursos IS 'PBI FacturacionRecursos — solo líneas Resource no Billable.';

-- ---------------------------------------------------------------------------
-- View: v_se_resumen_mensual
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_resumen_mensual AS
 SELECT v_se_facturacion.empresa,
    v_se_facturacion.year,
    v_se_facturacion.month,
    v_se_facturacion.ano_mes,
    v_se_facturacion.fecha_calculada,
    v_se_facturacion.codigo_unico_departamento,
    v_se_facturacion.tipo,
    sum(v_se_facturacion.facturado) AS total_venta,
    sum(v_se_facturacion.coste) AS total_gasto,
    sum(v_se_facturacion.facturacion_no_cero) AS total_facturacion_no_cero,
        CASE
            WHEN sum(v_se_facturacion.facturado) = 0::numeric THEN NULL::numeric
            ELSE (sum(v_se_facturacion.facturado) - sum(v_se_facturacion.coste)) / sum(v_se_facturacion.facturado)
        END AS margen_pct,
    sum(v_se_facturacion.facturado) - sum(v_se_facturacion.coste) AS margen_eur
   FROM v_se_facturacion
  GROUP BY v_se_facturacion.empresa, v_se_facturacion.year, v_se_facturacion.month, v_se_facturacion.ano_mes, v_se_facturacion.fecha_calculada, v_se_facturacion.codigo_unico_departamento, v_se_facturacion.tipo;
COMMENT ON VIEW public.v_se_resumen_mensual IS 'Métricas mensuales agregadas — equivalente medidas DAX base.';

-- ---------------------------------------------------------------------------
-- View: v_se_kpi_cards
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_se_kpi_cards AS
 WITH fact_p AS (
         SELECT v_se_facturacion.empresa,
            v_se_facturacion.year AS ano,
            sum(v_se_facturacion.facturado) AS total_venta,
            sum(v_se_facturacion.coste) AS total_gasto
           FROM v_se_facturacion
          WHERE v_se_facturacion.tipo = 'P'::text
          GROUP BY v_se_facturacion.empresa, v_se_facturacion.year
        ), obj AS (
         SELECT v_se_objectives.empresa,
            v_se_objectives.ano,
            sum(v_se_objectives.billing_target) AS billing_target,
            sum(v_se_objectives.cost_target) AS cost_target,
            sum(v_se_objectives.beneficio_eur) AS beneficio_eur
           FROM v_se_objectives
          GROUP BY v_se_objectives.empresa, v_se_objectives.ano
        )
 SELECT o.empresa,
    o.ano,
    round(o.billing_target, 2) AS obj_facturacion,
    round((o.billing_target - o.cost_target) / NULLIF(o.billing_target, 0::numeric) * 100::numeric, 2) AS obj_margen_pct,
    round(o.beneficio_eur, 2) AS obj_beneficio,
    round((o.billing_target - fp.total_venta) / NULLIF(fp.total_venta, 0::numeric) * 100::numeric, 2) AS obj_crecimiento_pct,
    round(fc.total_venta, 2) AS plan_facturacion,
    round((fc.total_venta - fc.total_gasto) / NULLIF(fc.total_venta, 0::numeric) * 100::numeric, 2) AS plan_margen_pct,
    round(fc.total_venta - fc.total_gasto, 2) AS plan_beneficio,
    round((fc.total_venta - fp.total_venta) / NULLIF(fp.total_venta, 0::numeric) * 100::numeric, 2) AS plan_crecimiento_pct
   FROM obj o
     LEFT JOIN fact_p fc ON fc.empresa = o.empresa AND fc.ano = o.ano
     LEFT JOIN fact_p fp ON fp.empresa = o.empresa AND fp.ano = (o.ano - 1);
COMMENT ON VIEW public.v_se_kpi_cards IS 'PBI Resumen — 8 KPI cards (Objetivos Anuales + Planificación Actual) por empresa y año.';

