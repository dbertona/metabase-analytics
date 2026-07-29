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

### Acceso (usuarios / navegador)

| Uso | URL |
|-----|-----|
| **Única URL válida para usuarios** | https://apps.powersolution.es/analytics/ |
| Dashboard Resumen | https://apps.powersolution.es/analytics/superset/dashboard/planificacion-ps-analytics/ |

- **Login:** Microsoft (Azure AD) — misma App Registration que Timesheet  
  Redirect: `https://apps.powersolution.es/analytics/oauth-authorized/azure`
- **Usuario local (fallback sin `AZURE_CLIENT_SECRET`):** `admin`
- **Idioma UI:** español (`BABEL_DEFAULT_LOCALE=es`; packs en `config/translations/es/`)

> **⛔ No usar la IP LAN en el navegador** (`http://192.168.36.100:8088/…`).  
> El SSO Azure y el path `/analytics` están publicados solo por DNS (`apps.powersolution.es`).  
> Entrar por IP provoca login/OAuth rotos o sesión inválida.  
> La IP `192.168.36.100:8088` queda **solo para scripts/API internos** (pull, setup, health).

## Gestión

| Acción | Comando |
|--------|---------|
| Iniciar | `./scripts/start.sh` |
| Parar | `./scripts/stop.sh` |
| Backup | `./scripts/backup.sh` |
| Logs | `docker compose logs -f superset` |
| **Pull UI → snapshot** | `SUPERSET_URL=http://192.168.36.100:8088/analytics python3 scripts/pull-superset-dashboard.py` |
| Regenerar dashboard | `SUPERSET_URL=http://192.168.36.100:8088/analytics python3 scripts/setup-superset-planificacion.py` (hace pull UI antes) |

> Los comandos de gestión usan IP LAN a propósito (API admin desde red interna).  
> **Probar o usar el dashboard en el navegador:** siempre `https://apps.powersolution.es/analytics/`.

**Importante:** cambios hechos a mano en la UI de Superset se **pisan** al regenerar.
Antes de regenerar, el setup hace **pull** a `exports/superset-dashboard/latest/` y avisa si hay
divergencia vs el snapshot previous. Ver [`exports/superset-dashboard/README.md`](exports/superset-dashboard/README.md)
y la regla Cursor [`.cursor/rules/superset-dashboard-ui-sync.mdc`](.cursor/rules/superset-dashboard-ui-sync.mdc)
(`alwaysApply: true` — obligatorio para cualquier agente).

## Estructura

```
├── docker-compose.yml          # Stack Superset
├── config/superset_config.py   # Feature flags y config
├── scripts/
│   ├── start.sh                # Arranque + vistas BI + dashboard
│   ├── apply-bi-views.sh       # Vistas SQL en PostgreSQL
│   ├── setup-superset-planificacion.py
│   ├── pull-superset-dashboard.py   # Trae estado UI antes de regenerar
│   └── sql/bi_dashboard_planificacion_views.sql
├── exports/superset-dashboard/      # Snapshots UI (latest/previous gitignored)
└── data/superset-home/         # Metadatos Superset (local)
```

## Capa de datos (BI)

Superset consulta vistas `bi_v_*` en PostgreSQL PS Analytics:

```bash
./scripts/apply-bi-views.sh
```

Fuente única: `scripts/sql/bi_dashboard_planificacion_views.sql`

## Dashboard Seguimiento Económico — Resumen (Fase 3)

Réplica del panel **Resumen** de Power BI (slug estable `planificacion-ps-analytics`).

- 8 tarjetas KPI (Objetivos Anuales + Planificación Actual)
- Tabla **Resumen mensual** agregada: AñoMes | Facturación | Coste | Margen % (filtro Tipo P/R)
- Filtros: Año, Empresas, Departamentos, Planificado/Real
- Gráficos de evolución mensual y facturación por probabilidad

**Filtros nativos (diseño canónico):** [`docs/FILTROS_DASHBOARD_PLANIFICACION.md`](docs/FILTROS_DASHBOARD_PLANIFICACION.md)  
**Tablas AG Grid (agentes):** [`docs/TABLAS_AG_GRID.md`](docs/TABLAS_AG_GRID.md) — receta §0 + regla
[`.cursor/rules/superset-table-ag-grid.mdc`](.cursor/rules/superset-table-ag-grid.mdc)  
**Changelog:** [`CHANGELOG.md`](CHANGELOG.md) — Apply filters es **manual** (sin auto-apply en 6.1).

**Datos:**
- Objetivos → `bc_objectives_by_department`
- Planificación Actual (P+R, paridad Resumen PBI) → `bi_v_planificacion_kpi`
- Tabla Resumen: sin Tipo = P+R; filtro Tipo P|R → `bi_v_evolucion_mensual`

## Seguimiento Económico (PBI)

Guía maestra: [`docs/GUIA_COMPLETA_ANALYTICS.md`](docs/GUIA_COMPLETA_ANALYTICS.md)

Views canónicas BC (`v_se_*`): fuente de verdad en `sql/views/seguimiento_economico_views.sql`
(cambios SQL de Analytics se mantienen y versionan en este repo).
Ver `sql/views/README.md`.

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
