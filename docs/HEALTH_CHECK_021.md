# Workflow 021 — Health Check Analytics vs BC

Reconciliación diaria entre **Business Central (OData)** y **PostgreSQL Analytics**.
Si hay diferencias, envía email desde `noreply@powersolution.es` a `dbertona@powersolution.es`.

## Qué compara (y qué NO)

PBI y Superset cuadran en **Planificación Actual = Tipo P + Tipo R** (`v_se_facturacion`).
Ese KPI **no** es la suma bruta de `planificacionMes` Open/Planning (excluye meses
cerrados, meses con ingresos reales, vigente `budget_date`, etc.).

Por eso el 021 **no** alerta por bruto de plan BC vs `bc_job_planning_line`.

| Check | BC | Analytics | Criterio |
|-------|----|-----------|----------|
| `tipo_r_sum` | `movimientosProyectosMes` year + Ingresos (ABS) | `bc_job_ledger_entry_month` Ingresos | fail si \|Δ\| > 0,5 € |
| `meses_cerrados_count` | `mesesCerrados` excl. PP/PY | `bc_meses_cerrados` | warn si Δ>50; fail si Δ>5 % |
| `budget0_past_with_invoice` | — | plan `budget_date_year=0` con importe en meses pasados | fail si > 0 |
| `sync_freshness_hours` | — | `MAX(sync_state)` entidades clave | warn si > 26 h |
| `planificacion_actual_p_plus_r` | — (contexto) | `SUM(facturado)` P+R en `v_se_facturacion` | solo info (OK) |

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
./scripts/deploy-n8n-workflow-021.sh

curl -sS -X POST 'https://apps.powersolution.es/n8n/webhook/analytics-health-check'

PGPASSWORD='…' psql -h 192.168.36.100 -p 5433 -U postgres -d postgres -c \
  "SELECT checked_at, company_name, check_name, bc_value, analytics_value, delta, status
   FROM analytics_health_log ORDER BY id DESC LIMIT 20;"
```

**Schedule:** lun–vie 07:00 (`Europe/Madrid`).

**Credenciales n8n (reutilizadas del 004):** Business Central OAuth2, Postgres PS_Analytics, Microsoft Outlook noreply.
