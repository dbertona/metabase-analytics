-- Plan Gastos congelado al cierre (no-Resource) desde PS_JobPlanningUnified.
-- Fuente sync: scripts/sync_historico_gastos.py (OData jobPlanningUnified).
-- Usado por bi_mv_gastos (tipo P en meses cerrados).
-- Paridad con bc_historico_mano_obra_mes (Resource).

CREATE TABLE IF NOT EXISTS public.bc_historico_gastos_mes (
    company_name          text NOT NULL,
    job_no                text NOT NULL,
    year                  integer NOT NULL,
    month                 integer NOT NULL,
    closing_month_code    text NOT NULL,
    nr                    text NOT NULL DEFAULT '',
    type_line             text NOT NULL DEFAULT '',
    cost                  numeric(18, 5) NOT NULL DEFAULT 0,
    quantity              numeric(18, 5) NOT NULL DEFAULT 0,
    probability           numeric(5, 2),
    updated_at            timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (company_name, job_no, year, month, closing_month_code, nr, type_line)
);

CREATE INDEX IF NOT EXISTS bc_historico_gastos_mes_ym_idx
    ON public.bc_historico_gastos_mes (company_name, year, month);

COMMENT ON TABLE public.bc_historico_gastos_mes IS
  'Plan Gastos del mes (year,month): coste no-Resource desde Unified ClosingMonthCode=M−1 '
  'con planningDate en ese mes. Proxy Gastos = Type <> Resource. cost = ProbabilizedCost(LCY).';
