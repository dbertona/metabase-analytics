-- Ledger detalle (Excel PBI «Movimientos» / Mayor analítico).
-- Fuente BC: movimientosProyectos (query 50205 PS_MovimientosProyectos).
-- Canal: workflow 004 → entity job_ledger_entry_line.
-- Signo BC sin × −1. PY se guarda; la API Apps excluye job_no LIKE 'PY%'.
-- No reutilizar bc_job_ledger_entry (vacía) ni bc_job_ledger_entry_month (SE).

CREATE TABLE IF NOT EXISTS public.bc_job_ledger_entry_line (
    company_name                     text NOT NULL,
    entry_no                         bigint NOT NULL,
    entry_type                       text,
    document_no                      text,
    job_no                           text,
    job_task_no                      text,
    no                               text,
    description                      text,
    quantity                         numeric(18, 5),
    original_unit_cost               numeric(18, 5),
    total_cost                       numeric(18, 5),
    unit_price                       numeric(18, 5),
    total_price                      numeric(18, 5),
    line_price                       numeric(18, 5),
    concepto_analitico_code          text,
    concepto_analitico_descripcion   text,
    departamento                     text,
    tecnologia                       text,
    tipologia                        text,
    timesheet_date                   date,
    document_date                    date,
    origen                           text,
    month                            integer,
    year                             integer,
    ng                               text,
    last_modified                    timestamptz,
    updated_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bc_job_ledger_entry_line_pkey
        PRIMARY KEY (company_name, entry_no)
);

CREATE INDEX IF NOT EXISTS bc_job_ledger_entry_line_year_idx
    ON public.bc_job_ledger_entry_line (company_name, year);

CREATE INDEX IF NOT EXISTS bc_job_ledger_entry_line_job_idx
    ON public.bc_job_ledger_entry_line (company_name, job_no);

CREATE INDEX IF NOT EXISTS bc_job_ledger_entry_line_origen_idx
    ON public.bc_job_ledger_entry_line (company_name, origen);

COMMENT ON TABLE public.bc_job_ledger_entry_line IS
  'Job Ledger línea (50205 movimientosProyectos) para Mayor analítico; signo BC; sync 004.';
