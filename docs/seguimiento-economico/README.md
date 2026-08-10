# Seguimiento Económico PS — capa Analytics

Informe origen: Power BI `Seguimiento Económico PS.pbix` (dataset en la nube, fuente **BC Production**).

> **Documentación maestra:** [004_SYNC_BC_ANALYTICS.md](../shared/analytics/004_SYNC_BC_ANALYTICS.md) — sync 004, vistas Analytics, paridad PBI y operaciones de datos.

## Objetivo

Mantener en **PostgreSQL Analytics** (VM 100) las vistas y tablas que alimentan:

- **Apps** (Seguimiento Económico / planificación)
- **Power BI** (paridad numérica documentada)

La UI Apache Superset está **retirada**.

## Repositorios

| Repo | Responsabilidad |
|------|-----------------|
| **superset-analytics** (este) | Spec PBI, SQL canónico (`v_se_*`, `bi_v_*`), workflow 004, docs de sync |
| **power-solution-apps** | Consumo Apps (fuera de alcance para cambios SQL/004 aquí) |

## Infraestructura (prod)

| Componente | Ubicación |
|--------------|-----------|
| PostgreSQL Analytics | VM 100 — `192.168.36.100:5433` (`supabase-db`) |
| n8n workflow 004 | VM 101 — `https://apps.powersolution.es/n8n/` |
| BC OData | Production (`BC_ENVIRONMENT=Production`) |

## Sync

```bash
curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'
```

Workflow: [d1f7647e114a486e](https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e)

## Paridad KPI PSI 2026

> Detalle: [ANALYTICS_FACTURACION_PBI_ALIGNMENT.md](../shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md)

```sql
SELECT tipo, ROUND(SUM(facturado)::numeric, 0)
FROM v_se_facturacion
WHERE empresa ILIKE '%Iberia%' AND year = 2026
GROUP BY tipo;

SELECT tipo, ROUND(SUM(coste)::numeric, 0)
FROM v_se_coste
WHERE empresa ILIKE '%Iberia%' AND year = 2026
GROUP BY tipo;
```

## Páginas del informe PBI (referencia)

1. **Resumen** — KPIs, margen, acumulados
2. **Unidad** — Pivot por concepto analítico (`bi_v_unidad`)
3. **Resumen Proyectos** — Tabla por proyecto (`bi_v_resumen_proyectos`)
4. **Facturación** — Pivot mensual (`bi_v_facturacion`)
5. **Gastos** — Pivot mensual costes (`bi_v_gastos`; excl. `type_line=Resource`)
6. **Mano de Obra** / **Recursos/Perfiles**

## Views SQL

Canónico en este repo:

- `sql/views/seguimiento_economico_views.sql`
- `scripts/sql/bi_dashboard_planificacion_views.sql`

Consumidores: Apps y PBI sobre `v_se_*` / `bi_v_*`.

## Documentación relacionada

- [004_SYNC_BC_ANALYTICS.md](../shared/analytics/004_SYNC_BC_ANALYTICS.md)
- [ANALYTICS_FACTURACION_PBI_ALIGNMENT.md](../shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md)
- [ACTUALIZAR_WORKFLOW_004.md](../ACTUALIZAR_WORKFLOW_004.md)
- [pbix-model-spec.md](./pbix-model-spec.md)
- [phase-2-sync-004.md](./phase-2-sync-004.md)
