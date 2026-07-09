-- =============================================================================
-- Tabla: login_company
-- =============================================================================
-- Almacena información de compañías para usuarios con rol LOGIN desde BC
-- Query BC: PS_LoginCompany (ID 50227)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.login_company (
    company_name VARCHAR(30) NOT NULL,
    role_id VARCHAR(20),
    email VARCHAR(250) NOT NULL,
    full_name VARCHAR(250),
    display_name VARCHAR(250),
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, email)
);

-- Índices para búsquedas frecuentes
CREATE INDEX IF NOT EXISTS idx_login_company_email ON public.login_company(email);
CREATE INDEX IF NOT EXISTS idx_login_company_company_name ON public.login_company(company_name);
CREATE INDEX IF NOT EXISTS idx_login_company_role_id ON public.login_company(role_id);

-- Trigger para actualizar updated_at
CREATE TRIGGER update_login_company_updated_at
    BEFORE UPDATE ON public.login_company
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comentarios
COMMENT ON TABLE public.login_company IS 'Información de compañías para usuarios con rol LOGIN desde BC (Query 50227)';
COMMENT ON COLUMN public.login_company.company_name IS 'Nombre de la compañía (Company Name)';
COMMENT ON COLUMN public.login_company.role_id IS 'ID del rol (Role ID = LOGIN)';
COMMENT ON COLUMN public.login_company.email IS 'Email de autenticación del usuario';
COMMENT ON COLUMN public.login_company.full_name IS 'Nombre completo del usuario';
COMMENT ON COLUMN public.login_company.display_name IS 'Nombre de visualización de la compañía';

