-- =============================================================================
-- Script para inicializar sync_state con todas las tablas de PS_Analytics
-- =============================================================================
-- Este script crea un registro en sync_state por cada tabla que necesita
-- sincronización desde Business Central
-- =============================================================================

-- Primero borrar todos los registros existentes
DELETE FROM public.sync_state;

-- Insertar los nuevos registros para Power Solution Iberia SL
INSERT INTO public.sync_state (company_name, entity, last_sync_at)
VALUES
    ('Power Solution Iberia SL', 'recursos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'ps_year', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'proyectos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'equipo_proyectos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'job_task', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'centros_de_responsabilidad', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'configuracion_usuarios', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'tecnologias', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'tipologias', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'departamentos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('Power Solution Iberia SL', 'movimientos_proyectos', '1970-01-01 00:00:00+00'::timestamp with time zone);

-- Insertar los nuevos registros para PS LAB CONSULTING SL
INSERT INTO public.sync_state (company_name, entity, last_sync_at)
VALUES
    ('PS LAB CONSULTING SL', 'recursos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'ps_year', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'proyectos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'equipo_proyectos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'job_task', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'centros_de_responsabilidad', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'configuracion_usuarios', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'tecnologias', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'tipologias', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'departamentos', '1970-01-01 00:00:00+00'::timestamp with time zone),
    ('PS LAB CONSULTING SL', 'movimientos_proyectos', '1970-01-01 00:00:00+00'::timestamp with time zone);

-- Verificar que se insertaron correctamente
SELECT
    company_name,
    entity,
    last_sync_at
FROM public.sync_state
ORDER BY entity;

