-- Plan Unidad (Structure) congelado por concepto en meses cerrados.
-- Fuente: bc_historico_planificacion_mes (Unified vía 004), grano
-- closing_month_code = YYYY.MM del propio mes de planificación.
-- Usado por bi_mv_unidad (tipo P en meses cerrados).
--
-- Nota: HistoricoPlanificacionMes aún no expone analiticConcept en Prod;
-- concepto_analitico_descripcion se rellena con description de Job (fallback).
-- Cuando BC exponga CA en Unified/histórico, regenerar este snapshot con CA.

CREATE TABLE IF NOT EXISTS public.bc_historico_unidad_mes (
    company_name                   text NOT NULL,
    job_no                         text NOT NULL,
    year                           integer NOT NULL,
    month                          integer NOT NULL,
    concepto_analitico_descripcion text NOT NULL DEFAULT '',
    cost                           numeric(18, 5) NOT NULL DEFAULT 0,
    updated_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bc_historico_unidad_mes_pkey
        PRIMARY KEY (company_name, job_no, year, month, concepto_analitico_descripcion)
);

CREATE INDEX IF NOT EXISTS bc_historico_unidad_mes_ym_idx
    ON public.bc_historico_unidad_mes (company_name, year, month);

COMMENT ON TABLE public.bc_historico_unidad_mes IS
  'Snapshot Plan Structure (Unified cierre del mes) para bi_mv_unidad; no afecta Fact.';
