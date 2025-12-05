-- =============================================================================
-- PS_Analytics - Definición REAL de Tablas (basada en workflow 004)
-- =============================================================================
-- Este archivo contiene las definiciones REALES de las tablas que usa el
-- workflow 004_sync_bc_to_ps_analytics.json
--
-- IMPORTANTE: Las tablas están en el esquema PUBLIC, NO en ps_analytics
-- =============================================================================

-- =============================================================================
-- 1. recursos
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.recursos (
    company_name TEXT,
    "no" VARCHAR(20) NOT NULL PRIMARY KEY,
    name VARCHAR(100),
    arbvrn_email VARCHAR(250),
    global_dimension1_code VARCHAR(20),
    calendario VARCHAR(50),
    fecha_de_baja DATE,
    fecha_de_alta DATE,
    subcontratacion BOOLEAN DEFAULT FALSE,
    perfil VARCHAR(100),
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índice único en "no" (ya es PRIMARY KEY, pero se mantiene para referencia)
-- ON CONFLICT ("no") en workflow

-- =============================================================================
-- 2. ps_year
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.ps_year (
    ps_year INTEGER PRIMARY KEY,
    company_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    -- Nota: ps_year no tiene updated_at porque es una tabla de referencia estática
);

-- ON CONFLICT (ps_year) en workflow

-- =============================================================================
-- 3. proyectos
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.proyectos (
    company_name TEXT,
    "no" VARCHAR(20) NOT NULL PRIMARY KEY,
    description VARCHAR(100),
    departamento VARCHAR(20),
    probability NUMERIC(5,2),
    tipo_proyecto VARCHAR(50),
    estado VARCHAR(50),  -- En workflow se inserta como texto, no INTEGER
    fecha_fin DATE,
    do_not_consolidate BOOLEAN DEFAULT FALSE,
    responsible VARCHAR(100),
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ON CONFLICT ("no") en workflow

-- =============================================================================
-- 4. equipo_proyectos
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.equipo_proyectos (
    company_name TEXT NOT NULL,
    job_no VARCHAR(20) NOT NULL,
    resource_no VARCHAR(20) NOT NULL,
    resource_name VARCHAR(100),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, job_no, resource_no)
);

-- ON CONFLICT (company_name, job_no, resource_no) en workflow

-- =============================================================================
-- 5. job_task (deshabilitado en workflow, pero definido)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.job_task (
    company_name TEXT NOT NULL,
    job_no VARCHAR(20) NOT NULL,
    "no" VARCHAR(50) NOT NULL,  -- task_no
    description TEXT,
    timesheet_blocked BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, job_no, "no")
);

-- ON CONFLICT (job_no, no, company_name) en workflow
-- NOTA: Orden diferente en workflow pero mismo resultado

-- =============================================================================
-- 6. centros_de_responsabilidad
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.centros_de_responsabilidad (
    company_name TEXT NOT NULL,
    code VARCHAR(20) NOT NULL,
    global_dimension1_code VARCHAR(20),
    email VARCHAR(250),
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, code)
);

-- ON CONFLICT (company_name, code) en workflow

-- =============================================================================
-- 7. configuracion_usuarios
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.configuracion_usuarios (
    company_name TEXT NOT NULL,
    user_id VARCHAR(132) NOT NULL,
    email VARCHAR(250),
    arbvrn_job_responsability_filter VARCHAR(20),
    projectteamfilter VARCHAR(20),
    departamento VARCHAR(20),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, user_id)
);

-- ON CONFLICT (company_name, user_id) en workflow

-- =============================================================================
-- 8. tecnologias
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.tecnologias (
    company_name TEXT NOT NULL,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100),
    dimension_code VARCHAR(20) DEFAULT 'TECNOLOGÍA',
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, code)
);

-- ON CONFLICT (company_name, code) en workflow

-- =============================================================================
-- 9. tipologias
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.tipologias (
    company_name TEXT NOT NULL,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100),
    dimension_code VARCHAR(20) DEFAULT 'TIPOLOGÍA',
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, code)
);

-- ON CONFLICT (company_name, code) en workflow

-- =============================================================================
-- 10. departamentos
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.departamentos (
    company_name TEXT NOT NULL,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100),
    dimension_code VARCHAR(20) DEFAULT 'DPTO',
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, code)
);

-- ON CONFLICT (company_name, code) en workflow

-- =============================================================================
-- 11. movimientos_proyectos
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.movimientos_proyectos (
    company_name TEXT NOT NULL,
    entry_no INTEGER NOT NULL,
    entry_type INTEGER,
    document_no VARCHAR(20),
    job_no VARCHAR(20) NOT NULL,
    job_task_no VARCHAR(20),
    "no" VARCHAR(20),
    description VARCHAR(100),
    quantity NUMERIC(15,5),
    original_unit_cost NUMERIC(15,5),
    total_cost NUMERIC(15,5),
    unit_price NUMERIC(15,5),
    total_price NUMERIC(15,5),
    global_dimension2_code VARCHAR(20),
    global_dimension1_code VARCHAR(20),
    global_dimension5_code VARCHAR(20),
    global_dimension4_code VARCHAR(20),
    timesheet_date DATE,
    document_date DATE,
    origen VARCHAR(10),
    line_price NUMERIC(15,5),
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Campos adicionales del SQL original (no insertados por workflow actualmente)
    month INTEGER,  -- De PS_JobLedgerEntryMonthYear
    year INTEGER,   -- De PS_JobLedgerEntryMonthYear
    concepto_analitico_code VARCHAR(20),  -- De ConceptoAnalitico
    concepto_analitico_descripcion VARCHAR(100),  -- De ConceptoAnalitico
    ng VARCHAR(50),  -- De DetalleProvedor
    PRIMARY KEY (company_name, entry_no)
);

-- ON CONFLICT (company_name, entry_no) en workflow

-- =============================================================================
-- 12. sync_state (usado por el workflow)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.sync_state (
    company_name TEXT NOT NULL,
    entity TEXT NOT NULL,
    last_sync_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT TIMESTAMPTZ '1970-01-01 00:00:00+00',
    PRIMARY KEY (company_name, entity)
);

-- =============================================================================
-- 13. sync_executions (usado para guardar resultados de ejecución)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.sync_executions (
    id SERIAL PRIMARY KEY,
    company_name TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE NOT NULL,
    details JSONB
);

-- =============================================================================
-- ÍNDICES ADICIONALES PARA RENDIMIENTO
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_recursos_company ON public.recursos(company_name);
CREATE INDEX IF NOT EXISTS idx_recursos_email ON public.recursos(arbvrn_email);
CREATE INDEX IF NOT EXISTS idx_recursos_departamento ON public.recursos(global_dimension1_code);

CREATE INDEX IF NOT EXISTS idx_proyectos_company ON public.proyectos(company_name);
CREATE INDEX IF NOT EXISTS idx_proyectos_departamento ON public.proyectos(departamento);
CREATE INDEX IF NOT EXISTS idx_proyectos_estado ON public.proyectos(estado);
CREATE INDEX IF NOT EXISTS idx_proyectos_responsible ON public.proyectos(responsible);

CREATE INDEX IF NOT EXISTS idx_equipo_proyectos_job ON public.equipo_proyectos(job_no);
CREATE INDEX IF NOT EXISTS idx_equipo_proyectos_resource ON public.equipo_proyectos(resource_no);

CREATE INDEX IF NOT EXISTS idx_movimientos_job ON public.movimientos_proyectos(job_no);
CREATE INDEX IF NOT EXISTS idx_movimientos_document_date ON public.movimientos_proyectos(document_date);
CREATE INDEX IF NOT EXISTS idx_movimientos_timesheet_date ON public.movimientos_proyectos(timesheet_date);
CREATE INDEX IF NOT EXISTS idx_movimientos_month_year ON public.movimientos_proyectos(year, month);

CREATE INDEX IF NOT EXISTS idx_centros_company ON public.centros_de_responsabilidad(company_name);
CREATE INDEX IF NOT EXISTS idx_configuracion_company ON public.configuracion_usuarios(company_name);
CREATE INDEX IF NOT EXISTS idx_tecnologias_company ON public.tecnologias(company_name);
CREATE INDEX IF NOT EXISTS idx_tipologias_company ON public.tipologias(company_name);
CREATE INDEX IF NOT EXISTS idx_departamentos_company ON public.departamentos(company_name);
CREATE INDEX IF NOT EXISTS idx_departamentos_code ON public.departamentos(code);
CREATE INDEX IF NOT EXISTS idx_departamentos_dimension_code ON public.departamentos(dimension_code);

-- =============================================================================
-- TRIGGERS PARA ACTUALIZAR updated_at
-- =============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_recursos_updated_at
    BEFORE UPDATE ON public.recursos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_proyectos_updated_at
    BEFORE UPDATE ON public.proyectos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_equipo_proyectos_updated_at
    BEFORE UPDATE ON public.equipo_proyectos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_centros_updated_at
    BEFORE UPDATE ON public.centros_de_responsabilidad
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_configuracion_updated_at
    BEFORE UPDATE ON public.configuracion_usuarios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tecnologias_updated_at
    BEFORE UPDATE ON public.tecnologias
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tipologias_updated_at
    BEFORE UPDATE ON public.tipologias
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_departamentos_updated_at
    BEFORE UPDATE ON public.departamentos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_movimientos_updated_at
    BEFORE UPDATE ON public.movimientos_proyectos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- COMENTARIOS
-- =============================================================================

COMMENT ON TABLE public.recursos IS 'Recursos humanos sincronizados desde BC (workflow 004)';
COMMENT ON TABLE public.ps_year IS 'Años de referencia para PS_Analytics';
COMMENT ON TABLE public.proyectos IS 'Proyectos/Jobs sincronizados desde BC (workflow 004)';
COMMENT ON TABLE public.equipo_proyectos IS 'Equipos asignados a proyectos (workflow 004)';
COMMENT ON TABLE public.job_task IS 'Tareas de proyectos (workflow 004 - deshabilitado)';
COMMENT ON TABLE public.centros_de_responsabilidad IS 'Centros de responsabilidad (workflow 004)';
COMMENT ON TABLE public.configuracion_usuarios IS 'Configuración de usuarios BC (workflow 004)';
COMMENT ON TABLE public.tecnologias IS 'Dimensiones de tecnologías (workflow 004)';
COMMENT ON TABLE public.tipologias IS 'Dimensiones de tipologías (workflow 004)';
COMMENT ON TABLE public.departamentos IS 'Departamentos sincronizados desde BC (Query PS_Departamentos ID 7000104)';
COMMENT ON TABLE public.movimientos_proyectos IS 'Movimientos contables de proyectos (workflow 004)';
COMMENT ON TABLE public.sync_state IS 'Estado de sincronización por entidad y compañía';
COMMENT ON TABLE public.sync_executions IS 'Registro de ejecuciones del workflow 004';

-- =============================================================================
-- VERIFICACIÓN
-- =============================================================================

-- Verificar que las tablas se crearon correctamente
SELECT
    schemaname,
    tablename,
    tableowner
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'recursos', 'ps_year', 'proyectos', 'equipo_proyectos', 'job_task',
    'centros_de_responsabilidad', 'configuracion_usuarios', 'tecnologias',
    'tipologias', 'departamentos', 'movimientos_proyectos', 'sync_state', 'sync_executions'
  )
ORDER BY tablename;


