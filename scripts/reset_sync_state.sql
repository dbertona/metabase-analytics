-- =============================================================================
-- Script para resetear todas las fechas de sync_state a fecha antigua
-- Esto fuerza una sincronización completa desde Business Central
-- =============================================================================
-- Uso: Ejecutar en Supabase SQL Editor o con psql
-- =============================================================================

-- Resetear TODOS los registros de sync_state a fecha antigua
UPDATE public.sync_state
SET last_sync_at = '1970-01-01 00:00:00+00'::timestamp with time zone;

-- Verificar el resultado
SELECT
    company_name,
    entity,
    last_sync_at,
    CASE
        WHEN last_sync_at = '1970-01-01 00:00:00+00'::timestamp with time zone
        THEN '✅ Reseteado'
        ELSE '❌ No reseteado'
    END AS estado
FROM public.sync_state
ORDER BY company_name, entity;

-- Contar registros reseteados
SELECT
    COUNT(*) AS total_registros,
    COUNT(CASE WHEN last_sync_at = '1970-01-01 00:00:00+00'::timestamp with time zone THEN 1 END) AS reseteados
FROM public.sync_state;

