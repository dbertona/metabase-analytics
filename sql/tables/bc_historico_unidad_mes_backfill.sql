-- Reload Plan Structure congelado (mismo mes de cierre) desde
-- bc_historico_planificacion_mes (canal 004). Sin OData bypass.
-- concepto: description de Job (CA aún no en Histórico/Prod API).

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

TRUNCATE TABLE public.bc_historico_unidad_mes;

INSERT INTO public.bc_historico_unidad_mes (
    company_name,
    job_no,
    year,
    month,
    concepto_analitico_descripcion,
    cost,
    updated_at
)
SELECT
    h.company_name,
    h.job_no::text,
    h.year,
    h.month,
    COALESCE(NULLIF(TRIM(h.description::text), ''), h.job_no::text) AS concepto_analitico_descripcion,
    SUM(COALESCE(h.cost, 0))::numeric(18, 5) AS cost,
    now() AS updated_at
FROM public.bc_historico_planificacion_mes h
WHERE h.tipo_proyecto ILIKE 'Structure'
  AND NULLIF(BTRIM(h.closing_month_code::text), '') IS NOT NULL
  AND h.closing_month_code = (h.year::text || '.' || lpad(h.month::text, 2, '0'))
  AND ABS(COALESCE(h.cost, 0)) > 0.0001
GROUP BY
    h.company_name,
    h.job_no,
    h.year,
    h.month,
    COALESCE(NULLIF(TRIM(h.description::text), ''), h.job_no::text);
