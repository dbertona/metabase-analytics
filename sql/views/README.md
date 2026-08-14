# SQL Views — Seguimiento Económico

Snapshot de las vistas `v_se_*` y helpers `se_*` alineado con la **BD analytics live**
(VM 100, regenerado 2026-07-23).

## ⚠️ Fuente de verdad

| Qué | Dónde |
|-----|--------|
| **Canónico (aplicar cambios)** | Este directorio: `sql/views/seguimiento_economico_views.sql` |
| **Capa dashboard Superset `bi_v_*`** | `scripts/sql/bi_dashboard_planificacion_views.sql` |
| **Documentación funcional** | `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md` |

**No apliques cambios SQL en prod a ciegas:** las vistas `v_se_*` alimentan KPIs
de Apps/PBI. Canal: `./scripts/deploy-004-gated.sh --yes --sql-only`.

## Aplicar cambios reales

```bash
# Gate (testing → prod). También cubre bi_mv_* / bi_v_*.
./scripts/deploy-004-gated.sh --yes --sql-only

# Solo testing, sin tocar prod
ANALYTICS_DSN='postgresql://postgres:analytics_testing_2025@192.168.36.103:5435/postgres' \
  ./scripts/apply-bi-views.sh --with-se
```

`apply-bi-views.sh` (sin `--refresh`) está bloqueado contra Analytics prod.

## Actualizar fuente canónica

Cuando cambie la lógica de negocio PBI/Superset:

1. Editar `sql/views/seguimiento_economico_views.sql`.
2. Gate en testing: `./scripts/deploy-004-gated.sh --yes --sql-only --no-prod`.
3. Si el cambio debe mover cifras: `--allow-figure-change` y validar vs PBI/BC.
4. Publicar: `./scripts/deploy-004-gated.sh --yes --sql-only --skip-copy`.
5. Actualizar `CHANGELOG.md` y documentación relacionada.

## Contenido vigente (resumen)

- `v_se_lineas_movimientos` → `bc_job_ledger_entry_month` (no `bc_job_ledger_entry`).
- `v_se_lineas_planificacion` → excluye meses con Ingresos reales en ledger;
  `invoice`/`facturado` = 0 si `line_type = Budget` (ventas solo Billable).
- Incluye fase 2: expedientes, meses cerrados, objetivos, histórico, KPI cards.
- `v_se_coste` → capa dedicada a Coste P/R (`SUM(coste)`); **no** sustituye `v_se_facturacion`
  (facturación canónica). Incluye `fuente` y `coste_raw` para diagnóstico vs PBI.

### KPI Coste (validación PBI)

```sql
SELECT tipo, ROUND(SUM(coste)::numeric, 2)
FROM v_se_coste
WHERE empresa ILIKE '%Iberia%' AND year = 2026
GROUP BY tipo;
-- Objetivo PBI: P ≈ 3.788.848 € | R ≈ 2.271.735 €
```
