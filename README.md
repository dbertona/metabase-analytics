# PS Analytics (capa datos)

Réplica de datos Business Central en **PostgreSQL Analytics** (prod VM 100; testing VM 103; DEV VM 102) y sync **n8n workflow 004**.

> Nombre histórico del repo: `superset-analytics`. La UI Apache Superset está **retirada**. Este repo mantiene SQL canónico (`v_se_*`, `bi_v_*`), scripts de apply y la definición del workflow 004.

## Gitea es el repositorio principal

- ✅ `git push gitea main`
- ❌ No push directo a GitHub (solo mirror)

**Gitea:** `http://192.168.36.104:3000/admin/superset-analytics`

## Qué hay aquí

| Área | Ubicación |
|------|-----------|
| Deploy Gitea (testing / prod / ambos) | `.github/workflows/deploy-analytics.yml` — `./scripts/deploy-analytics.sh` |
| Workflow 004 (BC → Analytics) | `src/workflows/004_sync_bc_to_ps_analytics.json` |
| Workflow 021 (health check) | `src/workflows/021_health_check_analytics_bc.json` |
| Vistas Seguimiento Económico | `sql/views/seguimiento_economico_views.sql` |
| Vistas BI Apps | `scripts/sql/bi_dashboard_planificacion_views.sql` |
| Docs sync | `docs/ACTUALIZAR_WORKFLOW_004.md`, `docs/shared/analytics/` |
| Spec SE | `docs/seguimiento-economico/` |

## Consumidores

- **Apps** (Seguimiento Económico / planificación) — pool Analytics solo lectura

## Conexión DB Analytics

Matriz DEV / testing / prod y backend Apps: [`docs/ANALYTICS_ENVIRONMENTS.md`](docs/ANALYTICS_ENVIRONMENTS.md)

```bash
# Prod
psql "postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres"
# Testing (SE Apps en testingapp apunta aquí)
psql "postgresql://postgres:analytics_testing_2025@192.168.36.103:5435/postgres"
```

## Deploy (como Timesheet)

Solo **manual** en Gitea (`workflow_dispatch`). No despliega al hacer push a `main`.

1. Merge a `main` (la Action no aparece hasta estar en la rama por defecto).
2. Gitea → **Actions** → **Deploy Analytics Multi-Environment**.
3. `environment`: `testing` (default), `production` o `ambos` (testing primero).
4. `scope`: `all` (004 + SQL + 021) o un subconjunto.
5. Si `production` o `ambos`: marcar **confirm_production**.

Prod 004/SQL = apply directo desde el repo (sin clon/canary). Testing aplica el repo a n8n 103 y Analytics `:5435` (021 sin cron).

CLI: `./scripts/deploy-analytics.sh --env testing|production --yes`

## Docs de entrada

1. `docs/ANALYTICS_ENVIRONMENTS.md` — entornos, backend, copia prod→testing
2. `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md`
3. `docs/shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`
4. `docs/ACTUALIZAR_WORKFLOW_004.md`

## Nota

Stack Docker Compose / scripts UI Superset (`setup-superset*`, `start*.sh`, `config/superset_*`) eliminados del repo.
