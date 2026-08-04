-- ANALYTICS DB ONLY — bc_expediente_mes: job_unit_no (OData jobUnitNo)
-- Motivo: dos unidades del mismo job-mes pueden compartir el mismo Planned Amount.
-- Sin job_unit_no, exactKey/DISTINCT ON (…, invoice) colapsa unidades distintas.
-- Ejemplo: PSI-OT-25-2005 / 2026-06 → unidades 04+05+06 = 39.103,06 (no 22.344,61).
-- Idempotente.

BEGIN;

ALTER TABLE public.bc_expediente_mes
  ADD COLUMN IF NOT EXISTS job_unit_no text NOT NULL DEFAULT '';

-- Recrear PK incluyendo job_unit_no (conserva el resto de columnas de la clave actual).
ALTER TABLE public.bc_expediente_mes
  DROP CONSTRAINT IF EXISTS bc_expediente_mes_pkey;

ALTER TABLE public.bc_expediente_mes
  ADD CONSTRAINT bc_expediente_mes_pkey PRIMARY KEY (
    company_name,
    job_no,
    year,
    month,
    budget_date_year,
    budget_date_month,
    status,
    month_closing_status,
    departamento,
    description,
    tipo_proyecto,
    probability,
    do_not_consolidate,
    job_unit_no
  );

COMMENT ON COLUMN public.bc_expediente_mes.job_unit_no IS
  'Unidad de job (OData jobUnitNo ← PS_RevenuePlanLine."Job Unit No."). Distingue filas con mismo invoice.';

COMMIT;
