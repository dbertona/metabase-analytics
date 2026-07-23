# Filtros nativos — Dashboard Planificación PS Analytics

> Repo canónico: **`superset-analytics`**  
> Regenerar: `python3 scripts/setup-superset-planificacion.py`  
> Vistas: `scripts/sql/bi_dashboard_planificacion_views.sql`

## Diseño (Superset 6.1.0)

| Pieza | Dataset | Motivo |
|-------|---------|--------|
| 8 tarjetas KPI (Obj/Plan) | `bi_v_planificacion_kpi` | Tiene `department_code` + `facturacion_real_anterior` → filtro Departamento y Crecimiento |
| Resumen / Evolución / Margen | `bi_v_evolucion_mensual` | Fuente de **valores** de filtros (Año, Empresa, Dept, Tipo) |
| Facturación por Probabilidad | `bi_v_facturacion_probabilidad` | Fuera del scope de filtros Año/Empresa/Dept (evita invalidar Apply) |

### Por qué Apply se quedaba deshabilitado (Superset 6.x)

`GET /api/v1/dashboard/.../datasets` solo expone columnas **referenciadas por charts**.
Las tarjetas `big_number` solo usaban métricas → no aparecían `year` / `empresa` /
`department_code` → el filtro se marcaba inválido (`not_in_datasource`) y **Apply**
permanecía gris.

**Fix canónico:** en cada KPI, `adhoc_filters` con `IS NOT NULL` sobre esas 3 columnas
(`dim_adhoc_filters()` en `setup-superset-planificacion.py`). No cambia los totales;
solo registra las columnas en el contexto del dashboard.

### Por qué los filtros apuntan a `bi_v_planificacion_kpi` (Año/Empresa/Dept)

Tras el fix de columnas, el dataset de las tarjetas KPI ya expone las dimensiones.
`Tipo P/R` sigue en `bi_v_evolucion_mensual` (solo existe ahí).

`Resumen mensual` también incluye dims en `all_columns` por robustez.

### Scopes

- Año / Empresas / Departamentos → tarjetas KPI + charts de evolución (no Probabilidad).
- Tipo P/R → solo Resumen / Evolución / Margen acumulado.
- `enableEmptyFilter: false` — en el código de Superset esta flag equivale al
  checkbox **«Filter value is required»** cuando está en `true`. Con `true` en
  filtros vacíos, **Apply queda deshabilitado** hasta rellenar todos.
  Usamos `false` (vacío permitido).
- Sin `cascadeParentIds` (cascada Empresa→Dept puede dejar validateStatus=error).
- `cross_filters_enabled: false` (evitar conflicto con filtros nativos).

## Regenerar sin perder el diseño

```bash
cd /home/superset-analytics   # o clone local
./scripts/apply-bi-views.sh
python3 scripts/setup-superset-planificacion.py
```

### Prefijo obligatorio de IDs (Superset 6.1)

Los IDs de filtro nativo **deben** empezar por `NATIVE_FILTER-` (p. ej.
`NATIVE_FILTER-EMPRESA`). El modal `FiltersConfigModal` usa `isFilterId()` con ese
prefijo. IDs legacy tipo `FILTER-EMPRESA` se muestran como
`[untitled customization]`, panel derecho vacío y Save deshabilitado.

## Historial relevante (2026-07-23)

1. KPI cards pasaron de `bi_v_kpi_anual_empresa` → `bi_v_planificacion_kpi`.
2. Vista KPI ampliada con `real_anterior_dept` y plan híbrido (meses cerrados = R).
3. Upgrade servidor: Apache Superset **4.1.2 → 6.1.0**.
4. Hotfixes en SQLite de VM 100 consolidados en este script (fuente de verdad).
5. Fix IDs `FILTER-*` → `NATIVE_FILTER-*` (modal de edición roto en 6.1).
