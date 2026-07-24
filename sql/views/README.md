# SQL Views — Seguimiento Económico

Snapshot de las vistas `v_se_*` y helpers `se_*` alineado con la **BD analytics live**
(VM 100, regenerado 2026-07-23).

## ⚠️ Fuente de verdad

| Qué | Dónde |
|-----|--------|
| **Canónico (aplicar cambios)** | Este directorio: `sql/views/seguimiento_economico_views.sql` |
| **Capa dashboard Superset `bi_v_*`** | `scripts/sql/bi_dashboard_planificacion_views.sql` |
| **Documentación funcional** | `docs/GUIA_COMPLETA_ANALYTICS.md` |

**No apliques cambios SQL sin validación previa en entorno** (DEV/PROD): las vistas
`v_se_*` alimentan KPIs y dashboards críticos.

## Aplicar cambios reales

Desde este repo, aplicando SQL directamente sobre la BD Analytics:

```bash
psql "postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres" \
  -f sql/views/seguimiento_economico_views.sql
```

## Actualizar fuente canónica

Cuando cambie la lógica de negocio PBI/Superset:

1. Editar `sql/views/seguimiento_economico_views.sql`.
2. Probar en DB Analytics (`psql ... -f`).
3. Validar KPIs (`v_se_facturacion`, `v_se_kpi_cards`) contra Power BI.
4. Actualizar `CHANGELOG.md` y documentación relacionada.

## Contenido vigente (resumen)

- `v_se_lineas_movimientos` → `bc_job_ledger_entry_month` (no `bc_job_ledger_entry`).
- `v_se_lineas_planificacion` → excluye meses con Ingresos reales en ledger + Distinct PBI.
- Incluye fase 2: expedientes, meses cerrados, objetivos, histórico, KPI cards.
