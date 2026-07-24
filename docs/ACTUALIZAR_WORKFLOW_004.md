# Workflow 004 — Sync BC → Analytics

> **Guía completa:** [superset-analytics/docs/GUIA_COMPLETA_ANALYTICS.md](../../../superset-analytics/docs/GUIA_COMPLETA_ANALYTICS.md)

## Arquitectura (2026-07)

| Componente | Ubicación |
|------------|-----------|
| **Workflow 004 (canónico en este repo)** | `src/workflows/004_sync_bc_to_ps_analytics.json` |
| **n8n producción** | `https://apps.powersolution.es/n8n/` (VM **101**, `n8n-prod`) |
| **ID workflow prod** | `d1f7647e114a486e` |
| **n8n DEV** | VM 102 — workflow ID `d57165bf41a34b8eb215` |
| **PostgreSQL Analytics** | VM **100** — `192.168.36.100:5433` (`supabase-db`) |
| **Superset** | VM **100** — `http://192.168.36.100:8088/` |

> **Retirado:** n8n en VM 100 (puerto 5678). No usar.

---

## Ejecutar sync

```bash
curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'

curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=pslab'
```

**BC:** `BC_ENVIRONMENT=Production` en n8n-prod.

---

## Actualizar workflow en n8n prod

### Opción A — API

```bash
cd superset-analytics
./scripts/update-n8n-workflow-004-api.sh
```

### Opción B — SQLite (hotfix con remapeo credenciales)

Ver `docs/shared/n8n/N8N_GUIDE.md` PASO 2.5 y 3:

```bash
# 1) Copiar JSON + scripts al servidor 101
# 2) docker stop n8n-prod
# 3) remap_n8n_credentials.py --source sqlite --db-path ... --workflow-name "004 - Sync Bc To Analytics"
# 4) update_n8n_workflow_sqlite.py d1f7647e114a486e ...
# 5) docker start n8n-prod
```

DB prod: `/var/lib/docker/volumes/n8n_n8n_data_clean/_data/database.sqlite`

---

## Verificar sync

```bash
sshpass -p 'PsAdmin2025' ssh ps_admin@192.168.36.100 \
  "docker exec supabase-db psql -U postgres -d postgres -c \"
SELECT * FROM v_se_kpi_cards WHERE empresa = 'Power Solution Iberia SL' AND ano = 2026;
\""
```

Esperado plan PSI 2026: **4.193.215 €** (`v_se_kpi_cards`, incluye tipo P + objetivos).

> Desglose solo tipo P en `v_se_facturacion`: **3.712.450 €** — ver `docs/GUIA_COMPLETA_ANALYTICS.md` §6.2.

---

## Referencias

- `src/workflows/004_sync_bc_to_ps_analytics.json` — definición del workflow en este repo
- `docs/GUIA_COMPLETA_ANALYTICS.md` — arquitectura y operación Analytics/Superset
- `docs/shared/n8n/N8N_GUIDE.md`
