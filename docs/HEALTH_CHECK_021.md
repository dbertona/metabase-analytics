# Workflow 021 — Health Check Analytics vs BC

Reconciliación diaria entre **Business Central (OData)** y **PostgreSQL Analytics**.
Si hay diferencias, envía email desde `noreply@powersolution.es` a `dbertona@powersolution.es`.

## Qué compara

| Check | BC | Analytics | Umbral |
|-------|----|-----------|--------|
| `tipo_r_sum` | `movimientosProyectosMes` year + `descripcionCA='Ingresos'` (ABS) | `bc_job_ledger_entry_month` Ingresos | ±0,5 € |
| `plan_count` | `planificacionMes` Open/Planning (excl. PP/PY) | `bc_job_planning_line` mismo filtro | 0 |
| `plan_sum` | suma invoice mismos filtros (ABS) | suma invoice Analytics | ±0,5 € |
| `meses_cerrados_count` | `mesesCerrados` excl. PP/PY | `bc_meses_cerrados` | 0 |
| `budget0_past_with_invoice` | — (señal interna) | líneas `budget_date_year=0` con importe en meses pasados | 0 |
| `sync_freshness_hours` | — | `MAX(sync_state.last_sync_at)` entidades clave | warn si > 26 h |

Empresas: **PSI** + **PS Lab**. Año: calendario UTC actual.

## Artefactos

| Pieza | Ruta |
|-------|------|
| Workflow canónico | `src/workflows/021_health_check_analytics_bc.json` |
| Tabla log | `sql/tables/analytics_health_log.sql` → `public.analytics_health_log` |
| Deploy | `./scripts/deploy-n8n-workflow-021.sh` |
| ID n8n prod | `a021healthcheck0001` |

## Operación

```bash
# Desplegar / actualizar en n8n VM 101
./scripts/deploy-n8n-workflow-021.sh

# Ejecutar a mano (webhook)
curl -sS -X POST 'https://apps.powersolution.es/n8n/webhook/analytics-health-check'

# Ver último resultado
PGPASSWORD='…' psql -h 192.168.36.100 -p 5433 -U postgres -d postgres -c \
  "SELECT checked_at, company_name, check_name, bc_value, analytics_value, delta, status
   FROM analytics_health_log ORDER BY id DESC LIMIT 20;"
```

**Schedule:** lun–vie 07:00 (`Europe/Madrid`).

**Credenciales n8n (reutilizadas del 004):** Business Central OAuth2, Postgres PS_Analytics, Microsoft Outlook noreply.

## Notas

- BC OData devuelve `invoice` de Ingresos en negativo; el check usa `ABS` en ambos lados.
- Paginación OData igual que el 004 (`@odata.nextLink`).
- Si solo falla `meses_cerrados_count`, revisar Transform MesesCerrados / re-sync 004.
- Si falla `budget0_past_with_invoice`, hay planificación sin versionar en meses pasados (caso Lab 2026-07).
