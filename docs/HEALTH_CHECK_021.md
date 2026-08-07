# Workflow 021 — Health Check Analytics vs BC

Reconciliación diaria entre **Business Central (OData)** y **PostgreSQL Analytics**.
Si hay diferencias, envía email desde `noreply@powersolution.es` a `dbertona@powersolution.es`.

## Qué compara

| Check | BC | Analytics | Criterio |
|-------|----|-----------|----------|
| `tipo_r_sum` | `movimientosProyectosMes` year + Ingresos (ABS) | `bc_job_ledger_entry_month` Ingresos | fail si \|Δ\| > 0,5 € |
| `tipo_p_planif_sum` | `planificacionMes` year — **SUM todas las líneas** (sin Distinct por importe); filtros estado + `budgetDate` = Transform 004 | `bc_job_planning_line` mismos filtros | fail si \|Δ\| > 0,5 € |
| `meses_cerrados_count` | `mesesCerrados` excl. PP/PY | `bc_meses_cerrados` | warn si Δ>50; fail si Δ>5 % |
| `budget0_past_with_invoice` | — | plan `budget_date_year=0` con importe en meses pasados | fail si > 0 |
| `sync_freshness_hours` | — | `MAX(sync_state)` entidades clave | warn si > 26 h |
| `planificacion_actual_p_plus_r` | — (contexto) | `SUM(facturado)` P+R en `v_se_facturacion` | solo info (OK) |

> **2026-08-07:** `tipo_p_planif_sum` alineado al Transform 004 (SUM sin Distinct).
> Antes el 021 **no** alertaba por plan bruto porque el Distinct PBI deflactaba
> Analytics vs BC/Excel (caso `PSI-OT-26-2001`). Ahora BC y tabla sync deben
> coincidir al céntimo. El KPI Apps/Superset (`v_se_facturacion` P+R) sigue
> siendo distinto (excluye meses cerrados / con Ingresos, etc.) → check `info`.

> **2026-08-05:** un fail en `tipo_r_sum` con Analytics “congelado” y BC al día
> suele ser **cierre de mes** en BC (`monthClosingLastModifiedDateTime` reciente,
> `lastModifiedDateTime` antiguo). El 004 ya descubre esos cambios vía partition
> overwrite de movimientos. Mitigación inmediata: upsert de las PKs faltantes o
> resync de partición year|month; ver `004_SYNC_BC_ANALYTICS.md` § flujo Movimientos.

Empresas: **PSI** + **PS Lab**. Año: calendario UTC actual.

## Email vs log: solo se alerta lo crítico

Para evitar fatiga de alarma por diferencias menores (p. ej. desajustes de
1-2 % en `meses_cerrados_count` por timing entre dos llamadas OData):

- **Siempre se loguea** cada check (ok/warn/fail) en `analytics_health_log`.
- **Solo se envía email si algún check quedó en `status = 'fail'`** en esa
  ejecución. Los `warn` (diferencias menores) quedan solo en la tabla para
  revisión periódica, sin interrumpir por email.
- Checks con tolerancia cero real: `tipo_r_sum`, `tipo_p_planif_sum` (dinero)
  y `budget0_past_with_invoice` (señal binaria de plan sin versionar en mes
  cerrado — el bug de PS Lab de julio 2026).

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
