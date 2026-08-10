-- Plan Unidad congelado por concepto analítico en meses ya cerrados.
-- Backfill puntual desde bc_job_planning_line (línea viva sincronizada por el 004),
-- filtrado por bc_meses_cerrados. BC no borra "Job Planning Line" al cerrar mes,
-- por eso la línea viva sigue sirviendo como fuente para este backfill histórico.
-- Usado por bi_mv_unidad (tipo P en meses cerrados, agregado por concepto_analitico).

CREATE TABLE IF NOT EXISTS public.bc_historico_unidad_mes (
    company_name                    text NOT NULL,
    job_no                          text NOT NULL,
    year                            integer NOT NULL,
    month                           integer NOT NULL,
    concepto_analitico_descripcion  text NOT NULL DEFAULT '',
    cost                            numeric(18, 5) NOT NULL DEFAULT 0,
    updated_at                      timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (company_name, job_no, year, month, concepto_analitico_descripcion)
);

CREATE INDEX IF NOT EXISTS bc_historico_unidad_mes_ym_idx
    ON public.bc_historico_unidad_mes (company_name, year, month);

COMMENT ON TABLE public.bc_historico_unidad_mes IS
  'Plan Unidad (Structure) del mes (year,month) por concepto analítico, congelado para meses '
  'cerrados. Backfill puntual desde bc_job_planning_line (live) + bc_meses_cerrados. '
  'cost = suma de cost de bc_job_planning_line para ese concepto/job/mes.';
