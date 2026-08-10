# PS Analytics (capa datos)

Réplica de datos Business Central en **PostgreSQL Analytics** (VM 100) y sync **n8n workflow 004**.

> Nombre histórico del repo: `superset-analytics`. La UI Apache Superset está **retirada**. Este repo mantiene SQL canónico (`v_se_*`, `bi_v_*`), scripts de apply y la definición del workflow 004.

## Gitea es el repositorio principal

- ✅ `git push gitea main`
- ❌ No push directo a GitHub (solo mirror)

**Gitea:** `http://192.168.36.104:3000/admin/superset-analytics`

## Qué hay aquí

| Área | Ubicación |
|------|-----------|
| Workflow 004 (BC → Analytics) | `src/workflows/004_sync_bc_to_ps_analytics.json` |
| Vistas Seguimiento Económico | `sql/views/seguimiento_economico_views.sql` |
| Vistas BI Apps | `scripts/sql/bi_dashboard_planificacion_views.sql` |
| Docs sync / PBI | `docs/ACTUALIZAR_WORKFLOW_004.md`, `docs/shared/analytics/` |
| Spec PBI / SE | `docs/seguimiento-economico/` |

## Consumidores

- **Apps** (Seguimiento Económico / planificación) — pool Analytics solo lectura
- **Power BI** — paridad documentada en `docs/shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`

## Conexión DB Analytics

```bash
docker run --rm --network host postgres:15 \
  psql "postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres"
```

## Docs de entrada

1. `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md`
2. `docs/shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`
3. `docs/ACTUALIZAR_WORKFLOW_004.md`

## Nota

Docker Compose / scripts legacy de Superset pueden seguir en el árbol; no están documentados ni operativos tras el retiro de la UI.
