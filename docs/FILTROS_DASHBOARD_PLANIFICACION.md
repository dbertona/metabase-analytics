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

### Por qué los filtros apuntan a `bi_v_evolucion_mensual`

En Superset 6.x, `GET /api/v1/dashboard/.../datasets` solo expone columnas **usadas por charts**.  
Si los filtros apuntan a un dataset cuyas columnas de dimensión no aparecen ahí, el botón **Apply filters** queda deshabilitado.

Por eso `Resumen mensual` incluye en `all_columns`: `empresa`, `year`, `department_code`, `tipo`, etc.

### Scopes

- Año / Empresas / Departamentos → tarjetas KPI + charts de evolución (no Probabilidad).
- Tipo P/R → solo Resumen / Evolución / Margen acumulado.
- `enableEmptyFilter: true` (no bloquear Apply por filtro vacío).
- `cross_filters_enabled: false` (evitar conflicto con filtros nativos).

## Regenerar sin perder el diseño

```bash
cd /home/superset-analytics   # o clone local
./scripts/apply-bi-views.sh
python3 scripts/setup-superset-planificacion.py
```

## Historial relevante (2026-07-23)

1. KPI cards pasaron de `bi_v_kpi_anual_empresa` → `bi_v_planificacion_kpi`.
2. Vista KPI ampliada con `real_anterior_dept` y plan híbrido (meses cerrados = R).
3. Upgrade servidor: Apache Superset **4.1.2 → 6.1.0**.
4. Hotfixes en SQLite de VM 100 consolidados en este script (fuente de verdad).
