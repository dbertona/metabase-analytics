# Filtros nativos — Dashboard Seguimiento Económico — Resumen

> Repo canónico: **`superset-analytics`**  
> Título UI: **Seguimiento Económico — Resumen** (slug estable `planificacion-ps-analytics`)  
> Regenerar: `SUPERSET_URL=http://192.168.36.100:8088/analytics python3 scripts/setup-superset-planificacion.py`  
> (el setup hace **pull UI automático** primero — ver `.cursor/rules/superset-dashboard-ui-sync.mdc`)  
> Pull solo: `python3 scripts/pull-superset-dashboard.py` → `exports/superset-dashboard/latest/`  
> (desde Mac sin Docker local: `SKIP_APPLY_BI_VIEWS=1` si las vistas BI ya están aplicadas)  
> Vistas: `scripts/sql/bi_dashboard_planificacion_views.sql`  
> **URL usuarios (solo DNS):** https://apps.powersolution.es/analytics/superset/dashboard/planificacion-ps-analytics/  
> ⛔ No abrir por IP LAN (`192.168.36.100:8088`) en el navegador — SSO solo por DNS.

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
└── Facturación por Probabilidad (width 6, height **26** — sync UI 2026-07-28)
```

Debajo: separación ~12px · Resumen mensual + Proyectos.
| Pieza | Alturas layout (grid units) | Notas |
|-------|----------------------------|-------|
| KPI cards Obj/Plan | height **8** | Etiquetas 11px sin recorte |
| Headers Objetivos / Planificación | height **2**, `SMALL_HEADER` | Menos hueco bajo el título |
| Facturación por Probabilidad | height **26** | Sync UI pull 2026-07-28 |
| Pieza | Dataset | Motivo |
|-------|---------|--------|
| 8 tarjetas KPI (Obj/Plan) | `bi_v_planificacion_kpi` | Plan por `tipo_label`; Obj solo filas P. Filtro Planificado/Real → tarjetas **Plan** |
| Resumen / Evolución / Margen | `bi_v_evolucion_mensual` | Fuente de **valores** del filtro Planificado/Real (`tipo_label`); dims también en Resumen |
| Facturación por Probabilidad | `bi_v_facturacion_probabilidad` | Al lado de KPIs (7+5); fuera del scope de filtros Año/Empresa/Dept; etiquetas `N%` e importes en `K€` (params + `tail_js`); sí entra en filtro **Proyectos** |
| Gastos (pestaña Unidad) → **Unidad** | `bi_v_unidad` | Pivot coste por concepto×mes; Structure fijo en la vista |
| Gastos (pestaña Gastos) | `bi_v_gastos` | Pivot coste Encabezado×mes; Operational + Completed/Open/Planning; total>0 |
| Facturación (pestaña) | `bi_v_facturacion` | Pivot facturado Encabezado×mes; Operational + Completed/Open/Planning; total>0 |

### Filtros configurados

| ID (obligatorio) | Nombre | Columna | Dataset | Scope |
|------------------|--------|---------|---------|-------|
| `NATIVE_FILTER-YEAR` | Año | `year` | KPI (ds planificacion) | Resumen + Unidad + Gastos + Facturación + Gráficos |
| `NATIVE_FILTER-EMPRESA` | Empresas | `empresa` | KPI | Resumen + Unidad + Gastos + Facturación + Gráficos |
| `NATIVE_FILTER-DEPT` | Departamentos | `department_code` | KPI | Resumen + Unidad + Gastos + Facturación + Gráficos |
| `NATIVE_FILTER-TIPO` | Planificado/Real | `tipo_label` | Evolución mensual | Resumen / Evolución / Margen / Proyectos / Unidad / Gastos / Facturación / **Plan KPI** |
| `NATIVE_FILTER-PROYECTO` | Proyectos | `proyecto` | Resumen proyectos | Resumen mensual / Proyectos / Evolución / Margen / Probabilidad / Gastos / Facturación (**no** KPIs ni Unidad) |

Valores del filtro Planificado/Real = `tipo_label` (Planificado|Real). Los charts
en scope deben exponer `tipo_label` en `adhoc_filters` (IS NOT NULL); si solo
exponen `tipo`, Apply no filtra.

### RLS server-side (`bc_user_configuration`)

Además de los filtros nativos, cada dataset BI lleva SQL virtual Jinja
(`ps_dept_filter` / `ps_row_filter` / `ps_team_jobs_sql`):

| Config usuario | Modo | Efecto |
|----------------|------|--------|
| `projectteamfilter = true` | `project_team` | Solo `job` ∈ `bc_job_team` del recurso (prioridad) |
| `departamento` vacío o `999` | `all` | Sin restricción RLS |
| `departamento = '1-XX'` | `department` | `department_code = '1-XX'` |

La UI muestra banner y oculta el filtro Departamentos cuando el ámbito está fijado.
Simulación Admin: cookie `ps_sim` + `/api/v1/ps/simulate`.

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
