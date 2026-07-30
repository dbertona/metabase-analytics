-- analytics_health_log — histórico de reconciliación Analytics ↔ BC
-- Workflow n8n 005 escribe una fila por check y empresa en cada ejecución.
-- Autorizado: 2026-07-30

CREATE TABLE IF NOT EXISTS public.analytics_health_log (
  id               bigserial PRIMARY KEY,
  checked_at       timestamptz NOT NULL DEFAULT now(),
  company_name     text        NOT NULL,
  year             integer     NOT NULL,
  check_name       text        NOT NULL,
  bc_value         numeric,
  analytics_value  numeric,
  delta            numeric,
  status           text        NOT NULL CHECK (status IN ('ok', 'warn', 'fail')),
  details          jsonb,
  alert_sent       boolean     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS analytics_health_log_checked_at_idx
  ON public.analytics_health_log (checked_at DESC);

CREATE INDEX IF NOT EXISTS analytics_health_log_company_status_idx
  ON public.analytics_health_log (company_name, status, checked_at DESC);

COMMENT ON TABLE public.analytics_health_log IS
  'Resultados del health check 005 (Analytics vs BC). Una fila por check/empresa/ejecución.';
