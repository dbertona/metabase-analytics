# Seguimiento Económico PS — Réplica Superset

Informe origen: Power BI `Seguimiento Económico PS.pbix` (dataset en la nube, fuente **BC Production**).

> **Documentación maestra:** [GUIA_COMPLETA_ANALYTICS.md](../GUIA_COMPLETA_ANALYTICS.md) — arquitectura, tablas, vistas, sync 004, KPIs y operaciones.

## Objetivo

Replicar en **Superset** (`https://apps.powersolution.es/analytics/` — solo DNS; ⛔ no IP LAN en navegador) las páginas del informe Power BI con paridad numérica respecto al modelo semántico PBI.

## Repositorios

| Repo | Responsabilidad |
|------|-----------------|
| **superset-analytics** (este) | Spec PBI, SQL canónico de Analytics (`v_se_*`, `bi_v_*`), exports de dashboards y docs |
| **power-solution-apps** | Fuera de alcance para cambios de Analytics en este workspace |

## Infraestructura (prod)

| Componente | Ubicación |
|--------------|-----------|
| PostgreSQL Analytics | VM 100 — `192.168.36.100:5433` (`supabase-db`) |
| Superset | VM 100 — `https://apps.powersolution.es/analytics/` (DNS; IP solo scripts) |
| n8n workflow 004 | VM 101 — `https://apps.powersolution.es/n8n/` |
| BC OData | Production (`BC_ENVIRONMENT=Production`) |

## Sync

```bash
curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'
```

Workflow: [d1f7647e114a486e](https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e)

## Paridad KPI PSI 2026

> **Estado:** ✅ Paridad KPI Resumen (2026-07-24b; revalidado live 2026-07-25).  
> Detalle: [ANALYTICS_FACTURACION_PBI_ALIGNMENT.md](../shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md)

### Totales (panel Resumen PBI vs analytics)

| Métrica | Fuente | Power BI | Analytics | Gap |
|---------|--------|----------|-----------|-----|
| Factura P | `v_se_facturacion` | 3.685.687 € | 3.685.687 € | 0 ✅ |
| Coste P | `v_se_coste` | 3.838.008 € | 3.838.008 € | 0 ✅ |
| Factura R | `v_se_facturacion` | 2.688.861 € | 2.688.861 € | 0 ✅ |
| Coste R | `v_se_coste` | 2.512.933 € | 2.513.515 € | +582 € (lag réplica) ✅ |

```sql
-- Facturación canónica
SELECT tipo, ROUND(SUM(facturado)::numeric, 0)
FROM v_se_facturacion
WHERE empresa ILIKE '%Iberia%' AND year = 2026
GROUP BY tipo;

-- Coste (capa separada)
SELECT tipo, ROUND(SUM(coste)::numeric, 0)
FROM v_se_coste
WHERE empresa ILIKE '%Iberia%' AND year = 2026
GROUP BY tipo;
```

## Fases del proyecto

| Fase | Estado | Entregable |
|------|--------|------------|
| **1** | ✅ | Views `v_se_*` + spec DAX/PQ |
| **2** | ✅ | Sync 004 + paridad KPI Resumen (P/R factura y coste) |
| **3** | ✅ | Dashboard Superset «Seguimiento Económico — Resumen» (`planificacion-ps-analytics`) |
| **4** | En curso | Resto de páginas PBI — **Unidad** ✅ · **Facturación** ✅ · **Gastos** ✅ |

**Dashboard Fase 3:** https://apps.powersolution.es/analytics/superset/dashboard/planificacion-ps-analytics/  
Regenerar (API LAN): `SKIP_APPLY_BI_VIEWS=1 SUPERSET_URL=http://192.168.36.100:8088/analytics python3 scripts/setup-superset-planificacion.py`

## Páginas del informe PBI

1. **Resumen** — KPIs objetivos, margen, acumulados, histórico planificación ✅
2. **Unidad** — Pivot por concepto analítico (`descripcionCA`) ✅ (`bi_v_unidad` + chart Unidad; Structure fijo)
3. **Resumen Proyectos** — Tabla por encabezado de proyecto ✅ (`bi_v_resumen_proyectos` + chart Proyectos; filtros PBI: Operational + estado Completed/Open/Planning)
4. **Facturación** — Pivot mensual facturado ✅ (`bi_v_facturacion` + chart Facturación; mismos filtros de estado + total > 0; meses 01–12)
5. **Gastos** — Pivot mensual costes ✅ (`bi_v_gastos` + chart Gastos; Operational + Completed/Open/Planning; coste > 0; Encabezado × meses)
6. **Mano de Obra** — Recursos y costes
7. **Mano de Obra Recursos/Perfiles** — Gauges horas planificadas vs imputables

## Filtros globales (slicers)

- `Años.Año` → `v_se_dim_anos`
- `Empresas.Display_Name` → `v_se_dim_empresas`
- `Departamentos.Descripcion` → `v_se_dim_departamentos`
- `Facturacion.Tipo` → `P` (planificado) / `R` (real)

## Views SQL

Canónico en este repo: `sql/views/seguimiento_economico_views.sql` + `scripts/sql/bi_dashboard_planificacion_views.sql`.  
Superset consulta **solo** vistas `v_se_*` y `bi_v_*` (ver guía completa §4.2).

## Documentación relacionada

- [GUIA_COMPLETA_ANALYTICS.md](../GUIA_COMPLETA_ANALYTICS.md)
- [ACTUALIZAR_WORKFLOW_004.md](../ACTUALIZAR_WORKFLOW_004.md)
- [pbix-model-spec.md](./pbix-model-spec.md)
- [phase-2-sync-004.md](./phase-2-sync-004.md)
