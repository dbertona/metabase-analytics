# SQL Views — Seguimiento Económico

Snapshot de las vistas `v_se_*` y helpers `se_*` alineado con la **BD analytics live**
(VM 100, regenerado 2026-07-23).

## ⚠️ Fuente de verdad

| Qué | Dónde |
|-----|--------|
| **Canónico (aplicar cambios)** | `power-solution-apps/supabase/migrations/*analytics_*.sql` |
| **Espejo (referencia)** | Este directorio: `seguimiento_economico_views.sql` |
| **Capa dashboard Superset `bi_v_*`** | `scripts/sql/bi_dashboard_planificacion_views.sql` |

**No uses este archivo como único deploy** sobre un entorno ya migrado: podrías
pisar o divergir de la cadena de migraciones de `power-solution-apps`.

## Aplicar cambios reales

Siempre desde `power-solution-apps` (nueva migración + script apply):

```bash
cd ../power-solution-apps   # o ruta al monorepo apps
# Ejemplo DEV:
ANALYTICS_DB_HOST=192.168.36.102 ANALYTICS_DB_CONTAINER=supabase-analytics-db-dev \
  ./scripts/apply-analytics-migration.sh supabase/migrations/<nueva_migracion>.sql
```

## Regenerar este espejo

Cuando la BD live cambie y quieras actualizar la referencia en este repo:

1. Exportar desde VM 100 (`pg_get_viewdef` / `pg_get_functiondef`) las
   funciones `se_*` y vistas `v_se_*` listadas en el header del `.sql`.
2. Sustituir `sql/views/seguimiento_economico_views.sql`.
3. Actualizar la fecha del header y una línea en `CHANGELOG.md`.

## Contenido vigente (resumen)

- `v_se_lineas_movimientos` → `bc_job_ledger_entry_month` (no `bc_job_ledger_entry`).
- `v_se_lineas_planificacion` → excluye meses con Ingresos reales en ledger + Distinct PBI.
- Incluye fase 2: expedientes, meses cerrados, objetivos, histórico, KPI cards.
