# Fase 2 — Ampliar workflow 004 para paridad PBI

Archivo canónico en este repo: `src/workflows/004_sync_bc_to_ps_analytics.json`

## Prioridad 1 — Movimientos por mes (bloquea tipo R)

**Problema:** 004 sincroniza `MovimientosProyectos` (50205) sin `month`/`year`. En DEV, `bc_job_ledger_entry` tiene 116k filas con fechas nulas.

**Solución:** Añadir rama (o sustituir) por API `MovimientosProyectosMes` (50214).

Campos requeridos en `bc_job_ledger_entry` o tabla nueva `bc_job_ledger_entry_month`:

- `month`, `year` (desde `PS_JobLedgerEntryMonthYear`)
- `type_line`, `line_type`
- `descripcion_ca` (concepto analítico)
- `budget_date_year`, `budget_date_month`, `status1` (mes cerrado)

Query BC: `Business-Central/src/Queries/PSMovimientosProyectosMes.Query.al`

## Prioridad 2 — Tablas nuevas

| sync_state.entity | API BC | Tabla Analytics propuesta |
|-------------------|--------|---------------------------|
| `expediente_mes` | expedienteMes | `bc_expediente_mes` |
| `meses_cerrados` | mesesCerrados | `bc_meses_cerrados` |
| `objectives_by_department` | objectivesByDepartaments | `bc_objectives_by_department` |
| `historico_planificacion_mes` | HistoricoPlanificacionMes | `bc_historico_planificacion_mes` |
| `dias_imputacion` | Dias de Imputacion | `bc_dias_imputacion` |

## Prioridad 3 — Recursos enriquecidos

PBI `RecursosHoras` usa campos de perfil desde API recursos. Verificar que `bc_resource` incluye columnas equivalentes a `perfil` si Superset lo necesita.

## Checklist despliegue

1. Migración SQL tabla(s) nueva(s) — cabecera `ANALYTICS DB ONLY`
2. Actualizar 004 en este repo (`src/workflows/004_sync_bc_to_ps_analytics.json`)
3. Aplicar en n8n prod con `./scripts/update-n8n-workflow-004-api.sh` (VM 101)
4. Aplicar SQL canónico desde este repo (`sql/views/seguimiento_economico_views.sql`) en prod (VM 100) — luego DEV/testing si aplica
5. Sync: `POST https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi`
6. Validar `v_se_kpi_cards` contra PBI

> **n8n:** solo `https://apps.powersolution.es/n8n/` (workflow `d1f7647e114a486e`). No hay n8n en VM 100.
