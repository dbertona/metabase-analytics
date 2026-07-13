# Seguimiento Económico PS — Réplica Superset

Informe origen: Power BI `Seguimiento Económico PS.pbix` (dataset en la nube, fuente **BC Production**).

> **Documentación maestra:** [GUIA_COMPLETA_ANALYTICS.md](../GUIA_COMPLETA_ANALYTICS.md) — arquitectura, tablas, vistas, sync 004, KPIs y operaciones.

## Objetivo

Replicar en **Superset** (`http://192.168.36.100:8088/`) las páginas del informe Power BI con paridad numérica respecto al modelo semántico PBI.

## Repositorios

| Repo | Responsabilidad |
|------|-----------------|
| **superset-analytics** (este) | Spec PBI, SQL de modelos Superset, exports de dashboards, docs |
| **power-solution-apps** | Migraciones Analytics, workflow **004**, scripts deploy |

## Infraestructura (prod)

| Componente | Ubicación |
|--------------|-----------|
| PostgreSQL Analytics | VM 100 — `192.168.36.100:5433` (`supabase-db`) |
| Metabase | VM 100 — `http://192.168.36.100:3000/` |
| n8n workflow 004 | VM 101 — `https://apps.powersolution.es/n8n/` |
| BC OData | Production (`BC_ENVIRONMENT=Production`) |

## Sync

```bash
curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'
```

Workflow: [d1f7647e114a486e](https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e)

## Paridad KPI PSI 2026 (validado 2026-07-07)

| Métrica | Power BI | Analytics |
|---------|----------|-----------|
| Real (tipo R) | 2.284.579 € | 2.284.579 € ✅ |
| Plan (tipo P) | 4.193.215 € | 4.193.215 € ✅ |

```sql
SELECT tipo, ROUND(SUM(facturado)::numeric, 0)
FROM v_se_facturacion
WHERE empresa = 'Power Solution Iberia SL' AND year = 2026
GROUP BY tipo;
```

## Fases del proyecto

| Fase | Estado | Entregable |
|------|--------|------------|
| **1** | ✅ | Views `v_se_*` + spec DAX/PQ |
| **2** | ✅ | Sync 004 Fase 2 + paridad KPI Resumen |
| **3** | Pendiente | Dashboard Metabase «Resumen» |
| **4** | Pendiente | Resto de páginas PBI |

## Páginas del informe PBI

1. **Resumen** — KPIs objetivos, margen, acumulados, histórico planificación
2. **Unidad** — Pivot por concepto analítico (`descripcionCA`)
3. **Resumen Proyectos** — Tabla por encabezado de proyecto
4. **Facturación** — Pivot mensual facturado
5. **Gastos** — Pivot mensual costes
6. **Mano de Obra** — Recursos y costes
7. **Mano de Obra Recursos/Perfiles** — Gauges horas planificadas vs imputables

## Filtros globales (slicers)

- `Años.Año` → `v_se_dim_anos`
- `Empresas.Display_Name` → `v_se_dim_empresas`
- `Departamentos.Descripcion` → `v_se_dim_departamentos`
- `Facturacion.Tipo` → `P` (planificado) / `R` (real)

## Views SQL

Canónico en `power-solution-apps/supabase/migrations/20260702180000_*` y fixes julio 2026.  
Metabase consulta **solo** vistas `v_se_*` (ver guía completa §4.2).

## Documentación relacionada

- [GUIA_COMPLETA_ANALYTICS.md](../GUIA_COMPLETA_ANALYTICS.md)
- [ACTUALIZAR_WORKFLOW_004.md](../ACTUALIZAR_WORKFLOW_004.md)
- [pbix-model-spec.md](./pbix-model-spec.md)
- [phase-2-sync-004.md](./phase-2-sync-004.md)
