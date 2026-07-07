# Seguimiento Económico PS — Réplica Metabase

Informe origen: Power BI `Seguimiento Económico PS.pbix` (dataset en la nube, fuente **BC Production**).

## Objetivo

Replicar en **Metabase prod** (`http://192.168.36.100:3000/`) las 7 páginas del informe Power BI con paridad numérica respecto al modelo semántico PBI.

**Entorno de trabajo actual:** Analytics **producción** (VM 100). DEV (102) queda para pruebas aisladas.

## Repositorios

| Repo | Responsabilidad |
|------|-----------------|
| **metabase-analytics** (este) | Spec PBI, SQL de modelos Metabase, exports de dashboards |
| **power-solution-apps** | Migraciones Analytics (`supabase/migrations`), workflow **004**, deploy `ops/metabase/` |

## Infraestructura

| Componente | Producción |
|--------------|------------|
| PostgreSQL Analytics | VM 100 — `192.168.36.100:5433` (`supabase-db`) |
| Metabase | VM 100 — `http://192.168.36.100:3000/` |
| **n8n (workflow 004)** | VM **101** — `https://apps.powersolution.es/n8n/` |
| BC OData | **Production** (`BC_ENVIRONMENT=Production` en n8n-prod) |

**Sync:**

```bash
curl -X POST 'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'
```

Workflow UI: `https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e`

> No usar n8n en VM 100 (retirado 2026-07-07). Ver `docs/ACTUALIZAR_WORKFLOW_004.md`.

## Fases

| Fase | Estado | Entregable |
|------|--------|------------|
| **1** | En curso | Views SQL `v_se_*` + dimensiones + spec DAX/PQ |
| **2** | Sync OK en prod | Workflow 004 Fase 2 (movimientos mes, expediente, objetivos, histórico) |
| **3** | Pendiente | Dashboard Metabase «Resumen» |
| **4** | Pendiente | Resto de páginas (Unidad, Proyectos, Facturación, Gastos, M.O.) |

## Páginas del informe PBI

1. **Resumen** — KPIs objetivos, margen, acumulados, histórico planificación
2. **Unidad** — Pivot por concepto analítico (`descripcionCA`)
3. **Resumen Proyectos** — Tabla por encabezado de proyecto
4. **Facturación** — Pivot mensual facturado
5. **Gastos** — Pivot mensual costes
6. **Mano de Obra** — Recursos y costes
7. **Mano de Obra Recursos/Perfiles** — Gauges horas planificadas vs imputables

## Filtros globales (slicers)

- `Años.Año`
- `Empresas.Display_Name` → `company_name` en Analytics
- `Departamentos.Descripcion`
- `Facturacion.Tipo` → `P` (planificado) / `R` (real)
- `Proyectos.Proyecto` (opcional por página)

## Views SQL (Analytics PostgreSQL)

Canónico en `power-solution-apps`:

```text
supabase/migrations/20260702180000_analytics_seguimiento_economico_views.sql
supabase/migrations/20260702200000_analytics_seguimiento_economico_phase2_views.sql
supabase/migrations/20260706110000_analytics_se_kpi_budget_filter.sql
```

Referencia espejo en `metabase-analytics/sql/views/`.

| View | Equivalente PBI | Fuente datos |
|------|-----------------|--------------|
| `v_se_dim_empresas` | Empresas | `companys` |
| `v_se_dim_anos` | Años | `bc_ps_year` + años en facturación |
| `v_se_dim_departamentos` | Departamentos | `bc_department` |
| `v_se_lineas_planificacion` | Lineas PLanificacion | `bc_job_planning_line` |
| `v_se_lineas_movimientos` | Lineas Proyectos | `bc_job_ledger_entry_month` |
| `v_se_lineas_expedientes` | Lineas Expedientes | `bc_expediente_mes` |
| `v_se_facturacion` | Facturacion | UNION planificación + movimientos + expediente + meses cerrados |
| `v_se_kpi_cards` | KPI Resumen | Objetivos + planificación tipo P |
| `v_se_facturacion_recursos` | FacturacionRecursos | Subconjunto Resource de facturación |

## Brechas conocidas (paridad PBI)

| Tema | Estado |
|------|--------|
| Objetivos anuales KPI | ✅ Paridad con PBI |
| Planificación actual KPI | ❌ Gap ~2,9 M€ vs 7,74 M€ — dedup `budgetDateMonth` en upsert/views |
| Crecimiento YoY plan | ❌ Base 2025 tipo P incompleta en views |

## Despliegue migraciones SQL

```bash
cd power-solution-apps

# Producción (VM 100)
./scripts/apply-analytics-migration.sh supabase/migrations/<archivo>.sql

# DEV (opcional)
ANALYTICS_DB_HOST=192.168.36.102 ANALYTICS_DB_CONTAINER=supabase-analytics-db-dev \
  ./scripts/apply-analytics-migration.sh supabase/migrations/<archivo>.sql
```

## Validación vs Power BI

```sql
SELECT * FROM v_se_kpi_cards
WHERE empresa = 'Power Solution Iberia SL' AND ano = 2026;
```

Referencias PBI (PSI 2026): plan facturación **7.740.330 €**, margen **6,69 %**, beneficio **517.605 €**.

## Documentación relacionada

- [pbix-model-spec.md](./pbix-model-spec.md) — Medidas DAX y Power Query
- [phase-2-sync-004.md](./phase-2-sync-004.md) — Extensiones workflow 004
- [ACTUALIZAR_WORKFLOW_004.md](../ACTUALIZAR_WORKFLOW_004.md) — n8n prod y sync
- `power-solution-apps/docs/architecture/DATABASES_SPLIT.md`
