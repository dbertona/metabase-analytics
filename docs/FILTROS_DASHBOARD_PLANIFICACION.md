# Filtros nativos — Dashboard Planificación PS Analytics

> Repo canónico: **`superset-analytics`**  
> Regenerar: `python3 scripts/setup-superset-planificacion.py`  
> Vistas: `scripts/sql/bi_dashboard_planificacion_views.sql`  
> URL: http://192.168.36.100:8088/superset/dashboard/planificacion-ps-analytics/

## Diseño (Superset 6.1.0)

| Pieza | Dataset | Motivo |
|-------|---------|--------|
| 8 tarjetas KPI (Obj/Plan) | `bi_v_planificacion_kpi` | Tiene `department_code` + `facturacion_real_anterior` → filtro Departamento y Crecimiento |
| Resumen / Evolución / Margen | `bi_v_evolucion_mensual` | Fuente de **valores** de filtros Tipo P/R; dims también en Resumen |
| Facturación por Probabilidad | `bi_v_facturacion_probabilidad` | Fuera del scope de filtros Año/Empresa/Dept (evita invalidar Apply) |

### Filtros configurados

| ID (obligatorio) | Nombre | Columna | Dataset | Scope |
|------------------|--------|---------|---------|-------|
| `NATIVE_FILTER-YEAR` | Año | `year` | KPI (ds planificacion) | KPI + evolución |
| `NATIVE_FILTER-EMPRESA` | Empresas | `empresa` | KPI | KPI + evolución |
| `NATIVE_FILTER-DEPT` | Departamentos | `department_code` | KPI | KPI + evolución |
| `NATIVE_FILTER-TIPO` | Tipo P/R | `tipo` | Evolución mensual | Solo Resumen / Evolución / Margen |

### Scopes y controlValues

- `enableEmptyFilter: false` — en el código de Superset esta flag equivale al
  checkbox **«Filter value is required»** cuando está en `true`. Con `true` en
  filtros vacíos, **Apply queda deshabilitado** hasta rellenar todos.
  Usamos `false` (vacío permitido).
- Sin `cascadeParentIds` (cascada Empresa→Dept puede dejar validateStatus=error).
- `cross_filters_enabled: false` (evitar conflicto con filtros nativos).
- Año por defecto: año calendario actual.

---

## UX: Apply filters (decisión 2026-07-23)

**Se mantiene el botón Apply** (comportamiento nativo de Superset 6.1).

No hay opción oficial de “aplicar al seleccionar” en filtros nativos. El
*instant filtering* de filtros legacy se eliminó por rendimiento; sigue siendo
petición abierta en Apache Superset ([discussion #20663](https://github.com/apache/superset/discussions/20663)).

| Alternativa | Estado |
|-------------|--------|
| Apply manual (nativo) | **Adoptado** |
| Parche frontend auto-apply | Descartado (deuda en cada upgrade de imagen) |

Con 4 filtros, Apply evita varias recargas de charts al afinar la selección.

---

## Lecciones / fallos resueltos (Superset 6.1)

### 1. Apply gris — columnas no expuestas

`GET /api/v1/dashboard/.../datasets` solo expone columnas **referenciadas por charts**.
Las tarjetas `big_number` solo usaban métricas → no aparecían `year` / `empresa` /
`department_code` → filtro inválido (`not_in_datasource`) → Apply gris.

**Fix:** en cada KPI, `adhoc_filters` con `IS NOT NULL` sobre esas 3 columnas
(`dim_adhoc_filters()` en `setup-superset-planificacion.py`). No cambia totales.

### 2. Modal `[untitled customization]` / panel vacío

Los IDs **deben** empezar por `NATIVE_FILTER-`. El modal usa `isFilterId()`.
IDs legacy `FILTER-EMPRESA` se tratan como customizations rotas → panel vacío,
Save disabled.

**Fix:** IDs `NATIVE_FILTER-YEAR|EMPRESA|DEPT|TIPO` en script + metadata del dashboard.

### 3. `enableEmptyFilter: true` bloquea Apply

Con “Filter value is required” y filtros vacíos, Apply permanece disabled.
Usar `enableEmptyFilter: false`.

---

## Regenerar sin perder el diseño

```bash
cd /home/superset-analytics   # o clone local
./scripts/apply-bi-views.sh
python3 scripts/setup-superset-planificacion.py
```

Tras regenerar: hard refresh del navegador (quitar `native_filters_key` viejo de la URL).

---

## Historial (2026-07-23)

1. KPI cards: `bi_v_kpi_anual_empresa` → `bi_v_planificacion_kpi`.
2. Vista KPI: `real_anterior_dept` + plan híbrido (meses cerrados = R).
3. Upgrade servidor: Apache Superset **4.1.2 → 6.1.0**.
4. Hotfixes SQLite VM 100 consolidados en el script canónico.
5. Fix IDs `FILTER-*` → `NATIVE_FILTER-*`.
6. Decisión: mantener Apply manual (sin auto-apply).
