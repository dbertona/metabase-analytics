-- =============================================================================
-- Tabla: departamentos
-- =============================================================================
-- Tabla para almacenar departamentos sincronizados desde Business Central
-- Query BC: PS_Departamentos (ID 7000104)
-- EntityName: 'Departamentos'
-- EntitySetName: 'Departamentos'
-- Dimension Code filtrado: 'DPTO'
-- =============================================================================

-- Crear la tabla
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

-- Índices para rendimiento
CREATE INDEX IF NOT EXISTS idx_departamentos_company ON public.departamentos(company_name);
CREATE INDEX IF NOT EXISTS idx_departamentos_code ON public.departamentos(code);
CREATE INDEX IF NOT EXISTS idx_departamentos_dimension_code ON public.departamentos(dimension_code);

-- Trigger para actualizar updated_at automáticamente
CREATE TRIGGER update_departamentos_updated_at
    BEFORE UPDATE ON public.departamentos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comentarios
COMMENT ON TABLE public.departamentos IS 'Departamentos sincronizados desde BC (Query PS_Departamentos ID 7000104)';
COMMENT ON COLUMN public.departamentos.company_name IS 'Nombre de la compañía';
COMMENT ON COLUMN public.departamentos.code IS 'Código del departamento (Code)';
COMMENT ON COLUMN public.departamentos.name IS 'Nombre del departamento (Name)';
COMMENT ON COLUMN public.departamentos.dimension_code IS 'Código de dimensión (siempre DPTO)';

-- Verificar que la tabla se creó correctamente
SELECT
    schemaname,
    tablename,
    tableowner
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename = 'departamentos';






