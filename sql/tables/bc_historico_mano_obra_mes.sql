-- Plan MdO congelado al cierre (Resource) desde PS_JobPlanningUnified.
-- Fuente sync: scripts/sync_historico_mano_obra.py (OData jobPlanningUnified).
-- Usado por bi_mv_mano_obra (tipo P en meses cerrados).

CREATE TABLE IF NOT EXISTS public.bc_historico_mano_obra_mes (
    company_name          text NOT NULL,
    job_no                text NOT NULL,
    year                  integer NOT NULL,
    month                 integer NOT NULL,
    closing_month_code    text NOT NULL,
    nr                    text NOT NULL DEFAULT '',
    type_line             text NOT NULL DEFAULT 'Resource',
    cost                  numeric(18, 5) NOT NULL DEFAULT 0,
    quantity              numeric(18, 5) NOT NULL DEFAULT 0,
    probability           numeric(5, 2),
    updated_at            timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (company_name, job_no, year, month, closing_month_code, nr)
);

CREATE INDEX IF NOT EXISTS bc_historico_mano_obra_mes_ym_idx
    ON public.bc_historico_mano_obra_mes (company_name, year, month);

COMMENT ON TABLE public.bc_historico_mano_obra_mes IS
  'Snapshot coste Resource (plan) por job/mes/recurso al cierre. '
  'Proxy MdO = Type Resource (sin CA en Unified). cost = ProbabilizedCost(LCY).';
