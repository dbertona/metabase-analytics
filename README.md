# 📊 PS Analytics — Apache Superset

Plataforma de Business Intelligence con **Apache Superset 6.1.0** para visualizaciones del ecosistema Power Solution.

**Integrado con:** PostgreSQL PS Analytics (Supabase) + sync n8n desde Business Central

> **Repositorio Gitea:** `superset-analytics` — stack BI con Apache Superset.

## 🚨 Gitea es el repositorio principal

- ✅ `git push gitea main`
- ❌ No push directo a GitHub (solo mirror)

**Gitea:** `http://192.168.36.104:3000/admin/superset-analytics`

**Mirror GitHub (solo lectura/respaldo):** `https://github.com/dbertona/superset-analytics` (si existe)

## Inicio rápido

```bash
cp env.example .env
# Editar .env (SUPERSET_SECRET_KEY, SUPERSET_ADMIN_PASSWORD)

./scripts/start.sh
```

- **URL:** http://192.168.36.100:8088
- **Dashboard:** http://192.168.36.100:8088/superset/dashboard/planificacion-ps-analytics/
- **Usuario:** `admin`

## Gestión

| Acción | Comando |
|--------|---------|
| Iniciar | `./scripts/start.sh` |
| Parar | `./scripts/stop.sh` |
| Backup | `./scripts/backup.sh` |
| Logs | `docker compose logs -f superset` |
| Regenerar dashboard | `python3 scripts/setup-superset-planificacion.py` |

## Estructura

```
├── docker-compose.yml          # Stack Superset
├── config/superset_config.py   # Feature flags y config
├── scripts/
│   ├── start.sh                # Arranque + vistas BI + dashboard
│   ├── apply-bi-views.sh       # Vistas SQL en PostgreSQL
│   ├── setup-superset-planificacion.py
│   └── sql/bi_dashboard_planificacion_views.sql
└── data/superset-home/         # Metadatos Superset (local)
```

## Capa de datos (BI)

Superset consulta vistas `bi_v_*` en PostgreSQL PS Analytics:

```bash
./scripts/apply-bi-views.sh
```

Fuente única: `scripts/sql/bi_dashboard_planificacion_views.sql`

## Dashboard Planificación PS Analytics

Réplica del informe Power BI — Objetivos Anuales y Planificación Actual.

- 8 tarjetas KPI (Facturación, Margen, Crecimiento, Beneficio × 2 secciones)
- Filtros: Año, Empresas, Departamentos, Tipo P/R
- Gráficos de evolución mensual y facturación por probabilidad

**Filtros nativos (diseño canónico):** [`docs/FILTROS_DASHBOARD_PLANIFICACION.md`](docs/FILTROS_DASHBOARD_PLANIFICACION.md)

**Datos:**
- Objetivos → `bc_objectives_by_department`
- Planificación (P/R híbrido) → vistas `v_se_*` / `bi_v_planificacion_kpi`
- Real (R) → `bc_job_ledger_entry_month`

## Seguimiento Económico (PBI)

Guía maestra: [`docs/GUIA_COMPLETA_ANALYTICS.md`](docs/GUIA_COMPLETA_ANALYTICS.md)

Views canónicas BC: `sql/views/seguimiento_economico_views.sql` y migraciones en `power-solution-apps`.

## n8n y sync BC

- Setup: `docs/SETUP_N8N_INICIAL.md`
- Workflow 004: `docs/ACTUALIZAR_WORKFLOW_004.md`
- Troubleshooting DNS: `docs/TROUBLESHOOTING_N8N_KONG_DNS.md`

## Puertos

| Puerto | Servicio |
|--------|----------|
| **8088** | Superset Web UI |
| 5433 | PostgreSQL PS Analytics (Supabase local) |

## Seguridad

⚠️ Cambiar `SUPERSET_SECRET_KEY` y `SUPERSET_ADMIN_PASSWORD` en producción.

## Migración desde Metabase (2026-07)

- **Metabase retirado** — no hay contenedores ni puerto 3000.
- **Directorio en VM:** renombrar `/home/metabase` → `/home/superset-analytics` (opcional, recomendado).
- **Datos legacy:** eliminar `data/postgres` (BD interna Metabase) si quedó en disco:

```bash
sudo rm -rf data/postgres
```

- **Servicio systemd:** actualizar ruta en `scripts/n8n-network.service` tras renombrar directorio.
