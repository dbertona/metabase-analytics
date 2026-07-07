# Workflow 004 — Sync BC → Analytics

## Arquitectura (2026-07)

| Componente | Ubicación |
|------------|-----------|
| **Workflow 004 (canónico)** | `power-solution-apps/apps/timesheet/src/workflows/004_sync_bc_to_analytics.json` |
| **n8n producción** | `https://apps.powersolution.es/n8n/` (VM **101**, contenedor `n8n-prod`) |
| **ID workflow en prod** | `d1f7647e114a486e` |
| **PostgreSQL Analytics** | VM **100** — `192.168.36.100:5433`, contenedor `supabase-db` |
| **Metabase prod** | `http://192.168.36.100:3000/` |

> **Retirado (2026-07-07):** el n8n local en VM 100 (`n8n-analytics.powersolution.es`, puerto 5678) **no debe usarse**. Era redundante y provocaba syncs contra credenciales OAuth incorrectas.

---

## Actualizar el workflow en n8n prod

Desde el repo **power-solution-apps**:

```bash
cd power-solution-apps/apps/timesheet/src/workflows

# Requiere N8N_API_KEY_PRODUCTION y acceso a apps.powersolution.es
N8N_ENV=production ./update_workflow_n8n.sh 004_sync_bc_to_analytics.json
```

Guía completa: `power-solution-apps/docs/shared/n8n/N8N_GUIDE.md`

---

## Ejecutar sync (PSI / PSLAB)

```bash
# Producción — único endpoint válido para Analytics
curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'

curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=pslab'
```

**Entorno BC:** `BC_ENVIRONMENT=Production` en n8n-prod (VM 101).

---

## Verificar en n8n UI

1. Abrir: [004 - Sync Bc To Analytics](https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e)
2. Comprobar `updatedAt` y nodos Fase 2 (PlanificacionMes, ExpedienteMes, MovimientosProyectos, etc.)
3. Credencial Postgres Analytics → host `192.168.36.100`, puerto **5433**

---

## Verificar datos en Analytics DB

```bash
sshpass -p 'PsAdmin2025' ssh ps_admin@192.168.36.100 \
  "docker exec supabase-db psql -U postgres -d postgres -c \"
SELECT * FROM v_se_kpi_cards
WHERE empresa = 'Power Solution Iberia SL' AND ano = 2026;
\""
```

---

## Script local de este repo

`scripts/update-n8n-workflow-004.sh` está **obsoleto** (apuntaba al n8n retirado de VM 100). Usar `update_workflow_n8n.sh` en **power-solution-apps**.

---

## Referencias

- `power-solution-apps/apps/timesheet/src/workflows/WORKFLOW_004_ANALYSIS.md`
- `power-solution-apps/docs/infrastructure/CONFIGURAR_BC_WORKFLOW_001.md`
- `docs/seguimiento-economico/README.md`
