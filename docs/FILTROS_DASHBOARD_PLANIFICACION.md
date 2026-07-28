# Filtros nativos — Dashboard Seguimiento Económico — Resumen

> Repo canónico: **`superset-analytics`**  
> Título UI: **Seguimiento Económico — Resumen** (slug estable `planificacion-ps-analytics`)  
> Regenerar: `SUPERSET_URL=http://192.168.36.100:8088 python3 scripts/setup-superset-planificacion.py`  
> (el setup hace **pull UI automático** primero — ver `.cursor/rules/superset-dashboard-ui-sync.mdc`)  
> Pull solo: `python3 scripts/pull-superset-dashboard.py` → `exports/superset-dashboard/latest/`  
> (desde Mac sin Docker local: `SKIP_APPLY_BI_VIEWS=1` si las vistas BI ya están aplicadas)  
> Vistas: `scripts/sql/bi_dashboard_planificacion_views.sql`  
> URL: http://192.168.36.100:8088/superset/dashboard/planificacion-ps-analytics/

## ⚠️ Edits en la UI vs regeneración

Cambios hechos a mano en Superset (mover charts, colores, métricas, filtros) **se pisan** al
ejecutar `setup-superset-planificacion.py`.

**Obligatorio para agentes:**

1. `python3 scripts/pull-superset-dashboard.py` (o dejar que el setup lo haga en paso 0)
2. Si hay divergencias vs `previous/` → avisar al usuario antes de regenerar
3. Incorporar al script lo que se quiera conservar

Detalle: [`exports/superset-dashboard/README.md`](../exports/superset-dashboard/README.md) · regla Cursor `superset-dashboard-ui-sync.mdc`.

---

## Ancho en pantallas ultrawide

El grid de Superset es fluido (100 % del viewport). En monitores ultrawide eso
estiraba KPI/tablas de forma poco legible.

**Solución (2026-07-28):** `max-width: 1440px` centrado en header + contenido
(`--ps-dash-max-width` en `dashboard_css` del setup). En laptops ≤1440 px el
layout sigue usando el 100 % del ancho disponible. El panel de filtros no entra
en ese techo (sigue en su columna).

Comparable a PBI en espíritu (lienzo acotado), pero adaptativo hacia abajo
(sin `transform: scale`).

---

## Diseño (Superset 6.1.0)

### Layout superior (KPI + Probabilidad)

```text
ROW-KPI-BAND
├── COLUMN-KPIS (width 6) — Facturación/Beneficio=2, Margen/Crecimiento=1
└── Facturación por Probabilidad (width 6, height **22** — compact −35% 2026-07-28)
```

Debajo: Resumen mensual (ancho 12) · Evolución + Margen (6+6).

| Pieza | Alturas layout (grid units) | Notas |
|-------|----------------------------|-------|
| KPI cards Obj/Plan | height **7** | Antes 10; padding/fuentes compactas |
| Headers Objetivos / Planificación | height **3**, `SMALL_HEADER` | Antes 4 / MEDIUM |
| Facturación por Probabilidad | height **22** | Antes 34 |
| Pieza | Dataset | Motivo |
|-------|---------|--------|
| 8 tarjetas KPI (Obj/Plan) | `bi_v_planificacion_kpi` | Tiene `department_code` + `facturacion_real_anterior` → filtro Departamento y Crecimiento |
| Resumen / Evolución / Margen | `bi_v_evolucion_mensual` | Fuente de **valores** de filtros Tipo P/R; dims también en Resumen |
| Facturación por Probabilidad | `bi_v_facturacion_probabilidad` | Al lado de KPIs (7+5); fuera del scope de filtros Año/Empresa/Dept; etiquetas `N%` e importes en `K€` (params + `tail_js`); sí entra en filtro **Proyectos** |
| Gastos (pestaña Unidad) | `bi_v_unidad` | Pivot coste por concepto×mes; Structure fijo en la vista |

### Filtros configurados

| ID (obligatorio) | Nombre | Columna | Dataset | Scope |
|------------------|--------|---------|---------|-------|
| `NATIVE_FILTER-YEAR` | Año | `year` | KPI (ds planificacion) | Resumen + Gráficos + Unidad |
| `NATIVE_FILTER-EMPRESA` | Empresas | `empresa` | KPI | Resumen + Gráficos + Unidad |
| `NATIVE_FILTER-DEPT` | Departamentos | `department_code` | KPI | Resumen + Gráficos + Unidad |
| `NATIVE_FILTER-TIPO` | Tipo P/R | `tipo` | Evolución mensual | Resumen / Evolución / Margen / Proyectos / Gastos |
| `NATIVE_FILTER-PROYECTO` | Proyectos | `proyecto` | Resumen proyectos | Resumen mensual / Proyectos / Evolución / Margen / Probabilidad (**no** KPIs ni Gastos) |

Valores del filtro Proyectos = mismos `encabezado` que la tabla Proyectos (Operational).
No añade columna visible a Resumen/Probabilidad: solo restringe filas al Apply.

### Scopes y controlValues

- `enableEmptyFilter: false` — en el código de Superset esta flag equivale al
  checkbox **«Filter value is required»** cuando está en `true`. Con `true` en
  filtros vacíos, **Apply queda deshabilitado** hasta rellenar todos.
  Usamos `false` (vacío permitido).
- Sin `cascadeParentIds` (cascada Empresa→Dept puede dejar validateStatus=error).
- `cross_filters_enabled: false` (evitar conflicto con filtros nativos).
- Año por defecto: año calendario actual.
- Badge/botón de filtros **por chart** oculto vía CSS del dashboard (la barra
  nativa Año/Empresa/Dept/Tipo se mantiene).
- Panel `[data-test=dashboard-filters-panel]`: `overflow-y: auto` (solo el panel;
  no el hijo sticky) para evitar scroll de página sin ocultar los controles.

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
