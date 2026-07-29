# Tablas AG Grid en Superset — Guía operativa (agentes)

> **Regla breve (alwaysApply):** `.cursor/rules/superset-table-ag-grid.mdc`  
> **Última actualización:** 2026-07-29  
> **Patrón de referencia (tabla corta):** chart **Proyectos** (`id=21`).  
> **Patrón de referencia (matriz mes×dim):** **Gastos** (`id=22`) + **Facturación** — ver **§12**.

Esta guía evita el calvario típico: tabla que “pinta” pero no llena el card, buscador en fila extra,
resize que vuelve atrás, anchos que no persisten, o **scroll horizontal inexistente** cuando no caben
las columnas.

---

## 0. Receta para agentes (leer esto primero)

### Objetivo

Una tabla Superset usable de verdad = **Python params + CSS dashboard + JS runtime**.
Si falta una de las tres piezas, fallará en producción aunque el chart exista.

### Archivos que se tocan (y solo esos)

| Pieza | Archivo | Qué hace |
|-------|---------|----------|
| Params / layout / CSS | `scripts/setup-superset-planificacion.py` | `viz_type`, métricas, `dashboard_css`, owners |
| Comportamiento runtime | `config/tail_js_custom_extra.html` | Altura, columnas, buscador, persistencia |
| Feature flag | `config/superset_config.py` | `AG_GRID_TABLE_ENABLED: True` |
| Vistas SQL (si hay datos nuevos) | `scripts/sql/bi_dashboard_planificacion_views.sql` | Dataset `bi_v_*` |

### URL correcta (no olvidar `/analytics`)

```bash
# Scripts/API (LAN, solo ops — no navegador)
SUPERSET_URL=http://192.168.36.100:8088/analytics

# Usuarios / navegador (única URL válida)
# https://apps.powersolution.es/analytics/
```

❌ `http://192.168.36.100:8088` sin `/analytics` → login API 404.  
❌ Abrir el dashboard por IP LAN en el navegador → SSO Azure no aplica; **usar solo el DNS**.

### Orden obligatorio (nunca invertir)

```text
1. Rama feat/ o fix/ (no main)
2. Leer esta guía + pull UI
3. Editar código local (Python / JS / SQL)
4. Commit + push a gitea
5. Regenerar dashboard (aplica CSS/params)
6. Si cambió tail_js → reiniciar contenedor Superset
7. Probar en navegador (checklist §9)
```

```bash
# Pull + regenerar (el setup ya hace pull en paso 0)
SKIP_APPLY_BI_VIEWS=1 SUPERSET_URL=http://192.168.36.100:8088/analytics \
  python3 scripts/setup-superset-planificacion.py

# Solo si cambió config/tail_js_custom_extra.html o plantillas Jinja:
docker restart superset   # o el nombre del contenedor en el compose de este repo
```

### Checklist mínimo (tabla “lista”)

- [ ] `viz_type = "ag-grid-table"`
- [ ] CSS altura completa + fuente (bloque §4)
- [ ] **NO** ocultar `.ag-body-horizontal-scroll` (§4.2)
- [ ] JS: IDs/claves propios (no reutilizar Proyectos/Gastos/Facturación)
- [ ] Buscador en cabecera (si `include_search`)
- [ ] Interceptar `sizeColumnsToFit` (evitar snapback)
- [ ] Pull UI → commit → push → regenerar → probar
- [ ] **Si es matriz mes×dim (estilo Gastos/Facturación):** seguir **§12** completo

---

## 0b. ¿Qué patrón clonar?

| Pedido del usuario | Clonar | Sección |
|--------------------|--------|---------|
| Tabla corta (dimensión + 2–4 métricas) | **Proyectos** | §0–§5 |
| Matriz **mes a mes** (dimensión + 01–12 + Total) | **Gastos / Facturación** | **§12** |
| Otra pestaña con otra matriz | §12 (una matriz por pestaña; reutilizar helpers) | **§12** |

---

## 1. Inventario actual (no reinventar)

| Chart | ID típico | Pestaña | Columnas | Buscador | Notas |
|-------|-----------|---------|----------|:--------:|-------|
| Resumen mensual | 17 | Resumen | `ano_mes` + 3 métricas | No | Encaja casi siempre; orden cronológico vía SQL/JS |
| Proyectos | 21 | Resumen | `proyecto` + 3 métricas | Sí | **Patrón canónico** de UX |
| Gastos | 22 | Unidad | concepto + 12 meses + Total | Sí | Muchas columnas → **scroll horizontal real** si no caben |
| Facturación | 23 | Facturación | Encabezado + 12 meses + Total | Sí | Misma matriz que Gastos; filtros Operational + estados |

Si el usuario pide “otra tabla como Proyectos”, clonar el patrón Proyectos.  
Si pide “matriz mes a mes” o “otra pestaña como Gastos/Facturación”, **§12** (no reinventar).

---

## 2. Feature flag

En `config/superset_config.py`:

```python
FEATURE_FLAGS = {
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "AG_GRID_TABLE_ENABLED": True,   # obligatorio
}
```

Sin este flag, `ag-grid-table` no aparece. Tras cambiar config: reiniciar Superset.

---

## 3. Parámetros Python (`setup-superset-planificacion.py`)

### 3.1 Tabla corta (tipo Proyectos / Resumen)

```python
def mi_tabla_params() -> dict:
    return {
        "adhoc_filters": dim_adhoc_filters("tipo"),  # si aplica cross-filter
        "query_mode": "aggregate",
        "groupby": ["campo_dimension"],
        "metrics": [
            metric_sum("facturacion", "Fact."),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": ['["Margen %", false]'],  # mayor → menor margen
        "row_limit": 5000,
        "server_pagination": False,   # True solo si >~10k filas
        "show_totals": True,
        "include_search": True,       # False en tablas cortas sin búsqueda
        "show_cell_bars": False,
        "color_pn": False,
        "align_pn": False,
        "table_timestamp_format": "smart_date",
        "column_config": {
            "campo_dimension": {
                "customColumnName": "Nombre visible",
                "truncateLongCells": True,
                "columnWidth": 280,  # fallback; el JS reparte el resto
            },
            "Fact.": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
                "truncateLongCells": True,
            },
            "Coste": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
                "truncateLongCells": True,
            },
            "Margen %": {
                "d3NumberFormat": ".2f",
                "showCellBars": False,
                "truncateLongCells": True,
            },
        },
    }
```

En `charts_config`:

```python
("Mi Tabla", "mi-slug", dataset_id, "ag-grid-table", mi_tabla_params()),
```

### 3.2 Tabla ancha (tipo Gastos: muchas columnas)

- Métricas/meses con anchos mínimos legibles (p. ej. 60–110 px).
- Columna fija a la derecha con `pinned` vía JS si hace falta (Total).
- **Aceptar scroll horizontal** cuando `suma_anchos > viewport`.
- No aplastar columnas hasta que el texto sea ilegible solo para “quitar el scroll”.

---

## 4. CSS del dashboard (`dashboard_css` en el setup)

Sustituir `Nombre del chart` / `Mi Tabla` por el nombre real del chart
(`data-test-chart-name`).

### 4.1 Bloque canónico (siempre)

```css
/* Cabeceras + celdas */
[data-test-chart-name*='Mi Tabla'] thead th,
[data-test-chart-name*='Mi Tabla'] .ag-header-cell {
  white-space: nowrap !important;
  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;
  font-size: 1.077em !important;
  border-bottom: 2px solid #d1d5db !important;
  box-shadow: none !important;
}
[data-test-chart-name*='Mi Tabla'] td,
[data-test-chart-name*='Mi Tabla'] .ag-cell {
  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;
  font-size: 1.077em !important;
}

/* Ocultar paginación / barras de celda (NO la barra horizontal AG Grid) */
[data-test-chart-name*='Mi Tabla'] .dt-length,
[data-test-chart-name*='Mi Tabla'] .ant-pagination,
[data-test-chart-name*='Mi Tabla'] .row-count-container,
[data-test-chart-name*='Mi Tabla'] .cell-bar,
[data-test-chart-name*='Mi Tabla'] .cell-bars {
  display: none !important;
}

/* Totales: ocultar etiqueta Resumen en la 1ª columna si aplica */
[data-test-chart-name*='Mi Tabla'] .ag-floating-bottom .ag-cell[col-id='campo_dimension'] {
  visibility: hidden !important;
}
[data-test-chart-name*='Mi Tabla'] .ag-floating-bottom .anticon {
  display: none !important;
}

/* Altura completa del card */
[data-test-chart-name*='Mi Tabla'] .chart-slice {
  display: flex !important;
  flex-direction: column !important;
  height: 100% !important;
  overflow: hidden !important;
}
[data-test-chart-name*='Mi Tabla'] .slice_container {
  flex: 1 1 auto !important;
  min-height: 0 !important;
  overflow: hidden !important;
}
[data-test-chart-name*='Mi Tabla'] .chart-container,
[data-test-chart-name*='Mi Tabla'] .slice_container > div {
  height: 100% !important;
}
[data-test-chart-name*='Mi Tabla'] [class*='ag-theme'],
[data-test-chart-name*='Mi Tabla'] .ag-root-wrapper,
[data-test-chart-name*='Mi Tabla'] .ag-root-wrapper-body,
[data-test-chart-name*='Mi Tabla'] .ag-root {
  height: 100% !important;
  flex: 1 1 auto !important;
}
```

### 4.2 Scroll horizontal — regla de oro (2026-07-28)

**Problema que ya sufrimos:** se ocultó `.ag-body-horizontal-scroll` con
`display: none` y se forzó `overflow-x: hidden` en los viewports para evitar
“scroll fantasma”. En pantallas estrechas / tablas anchas (Gastos) el contenido
desbordaba y **no había forma de desplazarse**.

| Hacer | No hacer |
|-------|----------|
| Dejar que AG Grid muestre la barra solo si hay overflow | `display: none` / `height: 0` en `.ag-body-horizontal-scroll` |
| `overflow-x: auto` en `.ag-center-cols-viewport` y `.ag-header-viewport` | `overflow-x: hidden` en esos viewports |
| Ajustar anchos con JS para **caber cuando quepa** | Encoger columnas por debajo de lo legible solo para eliminar scroll |
| Aceptar scroll si `meses × minWidth + texto + pinned > card` | Forzar `display: block !important` siempre (crea barra vacía) |

CSS correcto (condicional, sin ocultar la barra):

```css
[data-test-chart-name*='Mi Tabla'] .ag-center-cols-viewport,
[data-test-chart-name*='Mi Tabla'] .ag-header-viewport {
  overflow-x: auto !important;
}
/* NO añadir reglas que oculten .ag-body-horizontal-scroll */
```

---

## 5. JavaScript — `config/tail_js_custom_extra.html`

Sin JS no hay UX completa. Cada tabla nueva necesita **helpers propios**
(nombres, selectores, storage key, chart id).

### 5.1 Qué registrar (checklist JS)

| Capacidad | Qué implementar | Reutilizar de |
|-----------|-----------------|---------------|
| Localizar API | `findAgGridApi` (ya existe) | compartido |
| Altura card | selector en el loop de altura / `fixAgGridHeight` | Proyectos |
| Anchos iniciales | mapa propio; texto = resto del viewport; métricas compactas | `getDefaultProyectosWidths` / `getDefaultGastosWidths` |
| Anti-snapback | parchear `api.sizeColumnsToFit` | Proyectos / Gastos |
| Persistencia local | `localStorage` key **única** (`ps-<tabla>-col-widths-vN`) | Proyectos |
| Persistencia compartida | GET/PUT chart `column_config.*.columnWidth` | Proyectos |
| Buscador en header | proxy nativo + ocultar fila original | `placeProyectosSearchInHeader` |
| Idempotencia | marcar `api.__ps…Init`, no solo el DOM | todos |

### 5.2 Distribución de columnas (pocas métricas)

| Columna | Ancho inicial |
|---------|---------------|
| Dimensión textual | `max(280, viewport − métricas)` |
| Fact. / Coste | ~110 px |
| Margen % | ~100 px |

No autosizar al texto más largo: un nombre eterno empuja las métricas fuera.

### 5.3 Tabla ancha (Gastos)

1. Calcular anchos mínimos por mes + concepto + Total pinned.
2. Si la suma cabe → repartir sin holgura inútil a la derecha.
3. Si no cabe → **mantener mínimos** y dejar scroll horizontal (CSS §4.2).
4. No restaurar anchos viejos de `localStorage` que dejen hueco o corten Total.

### 5.4 Buscador en cabecera (si `include_search: True`)

1. No mover `#filter-text-box` (React lo puede romper).
2. Proxy nativo con clase/`aria-label` únicos.
3. Insertar antes de `.header-controls` (izquierda del ⋮).
4. En cada tecla: localizar input real y reenviar `value` + evento `input`.
5. Ocultar `.dropdown-controls-container` y poner `height:100%` al padre.

### 5.5 Persistencia de anchos

- Guardar solo `columnResized` con `source === "uiColumnResized"`.
- No persistir eventos de autosize / `sizeColumnsToFit`.
- Compartido: CSRF → GET chart → PUT chart (200). Un 403 = falta owner/`can_write`.
- Owners canónicos del dashboard: Admin (`1`) + dbertona (`2`); no ampliar `PS_Viewer`.

---

## 6. Flujo completo para una tabla nueva

1. Confirmar con el usuario: nombre, columnas, buscador sí/no, pestaña/layout.
2. Pull UI:  
   `SUPERSET_URL=http://192.168.36.100:8088/analytics python3 scripts/pull-superset-dashboard.py`
3. Vista SQL `bi_v_*` si hace falta → `apply-bi-views` (o dejar que el setup lo haga).
4. Función de params + entrada en `charts_config` + layout JSON.
5. CSS §4 (altura + scroll condicional).
6. JS §5 con IDs propios.
7. Commit + push `gitea`.
8. Regenerar setup (comando §0).
9. Reiniciar Superset si cambió Jinja/`tail_js`.
10. Validar §9 en navegador real (también con ventana estrecha).

---

## 7. Selectores estables (Superset 6.x)

| Elemento | Selector |
|----------|----------|
| Card por nombre | `[data-test-chart-name*='Nombre']` |
| Header | `[data-test='slice-header']` |
| Controles ⋮ | `.header-controls` |
| Contenedor | `.slice_container` |
| Tema AG Grid | `[class*='ag-theme']` |
| Root | `.ag-root-wrapper`, `.ag-root` |
| Viewport cuerpo | `.ag-center-cols-viewport` |
| Viewport cabecera | `.ag-header-viewport` |
| Barra scroll H | `.ag-body-horizontal-scroll` |
| Buscador nativo | `#filter-text-box`, `.dropdown-controls-container` |
| Por ID | `[data-test-chart-id='<id>']` |

Usar `data-test-*`. Evitar `.slice_header` (legacy).

---

## 8. Anti-patrones (NO repetir)

| Anti-patrón | Por qué duele | Hacer en su lugar |
|-------------|---------------|-------------------|
| Solo crear el chart en UI | Se pierde al regenerar | Código en setup + JS |
| `viz_type: "table"` (legacy) | Sin resize/buscador AG | `ag-grid-table` |
| Ocultar scroll horizontal | Pantallas estrechas inutilizables | `overflow-x: auto`; no `display:none` en la barra |
| Un solo JS compartido para 2 tablas | IDs/storage cruzados | Keys y funciones por chart |
| Mover el input React del buscador | Deja de filtrar | Proxy + reenvío de eventos |
| Commit después de aplicar en servidor | Deploy sin el fix | Commit → push → aplicar |
| `SUPERSET_URL` sin `/analytics` | 404 login | URL con `/analytics` |
| `SKIP_SUPERSET_PULL=1` sin OK usuario | Se pisan edits UI | Pull siempre |
| Encoger meses a <~60 px | Números ilegibles | Scroll horizontal |

---

## 9. Validación obligatoria

### 9.1 Navegador

- Columnas visibles; si caben → sin barra; si no caben → **scroll horizontal usable**.
- Probar con ventana estrecha (~900 px) y pestaña Unidad (Gastos).
- Texto en una línea con elipsis; métricas legibles.
- Buscador antes de ⋮; filtra; no añade fila.
- Grid a la misma altura inferior que tablas hermanas.
- Totales visibles; resize sin snapback; refresh conserva anchos.
- Consola sin errores nuevos.

### 9.2 Servidor / API

- `http://192.168.36.100:8088/analytics/health` → OK.
- GET/PUT chart 200 al persistir anchos compartidos.
- Owners + rol editor mínimos (no `can_write` global a viewers).

### 9.3 Código / Git

- `python3 -m py_compile scripts/setup-superset-planificacion.py`
- Sintaxis JS del template; `git diff --check`
- Commit + push `gitea` **antes** de regenerar/aplicar

---

## 10. Troubleshooting rápido

| Síntoma | Causa | Solución |
|---------|-------|----------|
| Tipo de chart desconocido | Flag AG Grid off | `AG_GRID_TABLE_ENABLED` + restart |
| Login script 404 | URL sin `/analytics` | Corregir `SUPERSET_URL` |
| Tabla no llena el card | Falta CSS/JS altura | §4 + registrar en JS |
| Gastos ~560 px / card vacío; Facturación OK | Coma CSS: `[A],[B] .hijo` solo aplica a B | Usar `:is([A],[B]) .hijo` (nunca la coma suelta) |
| Buscador en otra fila / no filtra | Sin proxy o sin setter nativo | §5.4 |
| Resize vuelve atrás | `sizeColumnsToFit` de Superset | Parchear API |
| Ancho no viaja a otro PC | Sin PUT `column_config` / 403 | Owners + `can_write Chart` |
| Template JS no cambia | Caché Jinja | Restart contenedor + hard refresh |
| Texto partido en filas | Sin `truncateLongCells` | Activarlo en `column_config` |
| **No hay scroll horizontal** | CSS oculta barra / `overflow-x: hidden` | §4.2 — quitar hide, usar `auto` |
| Scroll fantasma vacío | `display:block !important` forzado | Dejar comportamiento nativo AG Grid |
| Pie Total recortado | Overflow del card / altura mal | Revisar flex altura; no `overflow:visible` agresivo |
| Flash `"N/A"` en meses vacíos | Plugin AG Grid formatea NULL | §12.6 — `valueFormatter` + modo light |
| Scroll lento en Chrome Retina | DPR 2 + DOM AG Grid + JS pesado | §12.7 — no observer en scroll; `tuneAgGridScrollPerf` |

---

## 12. Receta matriz mes × dimensión (Gastos / Facturación) ⭐

> **Usar esta sección** al crear **otra pestaña** con tabla ancha (concepto/proyecto/… × meses 01–12 + Total).  
> Referencias de código: Gastos (`id≈22`) y Facturación (`id≈23`).  
> **No meter varias matrices en Resumen** — una matriz por pestaña.

### 12.1 Piezas obligatorias (todas)

| # | Pieza | Archivo | Qué clonar |
|---|-------|---------|------------|
| 1 | SQL materializado | `scripts/sql/bi_dashboard_planificacion_views.sql` | `bi_mv_unidad` / `bi_mv_facturacion` → `bi_mv_<nombre>` + wrapper `bi_v_<nombre>` |
| 2 | REFRESH en sync | `src/workflows/004_sync_bc_to_ps_analytics.json` | Incluir la MV nueva en el nodo *Refresh BI Materialized Views* |
| 3 | Params chart | `scripts/setup-superset-planificacion.py` | `_month_pivot_params(...)` + pestaña + `charts_config` |
| 4 | CSS altura/scroll | mismo setup → `dashboard_css` | Selectores `:is([...])` (nunca coma suelta) |
| 5 | JS runtime | `config/tail_js_custom_extra.html` | Detector + persistencia + buscador + anti-N/A + tune scroll |
| 6 | Apply SQL | `./scripts/apply-bi-views.sh` | Tras commit; en prod/VM según runbook |

Una matriz “lista” = **SQL + Python + CSS + JS + REFRESH 004**. Falta una → se rompe al regenerar o al sync.

### 12.2 Reglas de producto / rendimiento

1. **Una sola AG Grid matriz por pestaña** (nunca 2 matrices visibles a la vez).
2. Resumen no debe ganar charts de este tipo (carga inicial).
3. SQL debe devolver **NULL** en meses sin actividad (`SUM(...) FILTER`), **no** `0` ni `''` — el `"N/A"` lo inventa el plugin AG Grid en el cliente; **no se arregla en SQL** (cambiar a texto rompe totales/`d3NumberFormat`).
4. Chrome Retina (DPR 2) será más pesado que Cursor (DPR 1); es esperado. Ver §12.7.
5. Reutilizar helpers existentes; **no** copiar/pegar un segundo `MutationObserver` por chart.

### 12.3 SQL — plantilla `bi_mv_*` + wrapper

Patrón canónico (Facturación):

```sql
CREATE MATERIALIZED VIEW bi_mv_<slug> AS
SELECT
    f.empresa,
    f.year,
    f.departamento AS department_code,
    d.department_name,
    f.tipo,
    CASE f.tipo
        WHEN 'P' THEN 'Planificado'
        WHEN 'R' THEN 'Real'
        ELSE COALESCE(f.tipo::text, '')
    END AS tipo_label,
    -- … filtros de negocio (tipo_proyecto, estado, …)
    <dim_expr> AS <dim_col>,          -- p. ej. encabezado AS proyecto
    SUM(<metrica>) FILTER (WHERE f.month = 1) AS m01,
    -- … m02 … m12
    SUM(<metrica>) AS total
FROM <fuente_v_se_*> f
LEFT JOIN mb_v_dim_departamento d
  ON d.company_name = f.empresa AND d.department_code = f.departamento
WHERE … filtros PBI …
GROUP BY …
HAVING ABS(SUM(<metrica>)) > 0.0001;

CREATE INDEX … ON bi_mv_<slug> (empresa, year);
CREATE INDEX … ON bi_mv_<slug> (department_code);
CREATE INDEX … ON bi_mv_<slug> (tipo_label);
CREATE INDEX … ON bi_mv_<slug> (<dim_col>);

CREATE VIEW bi_v_<slug> AS SELECT * FROM bi_mv_<slug>;
```

| Existente | Dimensión | Métrica | Filtros típicos |
|-----------|-----------|---------|-----------------|
| `bi_v_unidad` | `concepto_analitico` | `coste` | Structure (ver SQL) |
| `bi_v_facturacion` | `proyecto` (encabezado) | `facturado` | Operational + Completed/Open/Planning |

Tras crear la MV: añadirla al **REFRESH** del workflow **004** y aplicar con `./scripts/apply-bi-views.sh` (+ `--refresh` si solo refrescas).

### 12.4 Python — params y pestaña

Usar el helper existente (no duplicar la lista de meses a mano):

```python
def mi_matriz_params() -> dict[str, Any]:
    """Matriz mes a mes — mismo contrato que Gastos/Facturación."""
    return _month_pivot_params(
        dim_col="<dim_col>",          # columna en bi_v_*
        dim_label="<Etiqueta UI>",    # cabecera (Concepto / Encabezado / …)
        dim_width=280,                # o 220 como Gastos
        order_label="<orden_*>",      # SQL ORDER BY dimensión
    )
```

`_month_pivot_params` ya fija: `query_mode=aggregate`, métricas `m01`…`m12`+`total` con formato EUR, `row_limit=5000`, `show_totals=True`, `include_search=True`, `show_cell_bars=False`, `order_by_cols` por dimensión.

En `charts_config` / tabs del setup:

```python
("Mi Matriz", "mi-matriz-slug", dataset_id, "ag-grid-table", mi_matriz_params()),
```

- Crear **pestaña propia** en el layout del dashboard.
- Registrar el chart en `chartsInScope` de los filtros nativos que apliquen (Año, Empresa, Dept, Tipo, Proyecto…).
- Dataset: apuntar a `bi_v_<slug>` (no a la MV cruda si el wrapper es lo que usa RLS/Superset).

### 12.5 CSS — altura + scroll (coma prohibida)

Copiar el bloque de Gastos/Facturación en `dashboard_css`. **Obligatorio** usar `:is(...)`:

```css
/* ✅ Correcto — ambos charts */
:is([data-test-chart-name*='Gastos'],[data-test-chart-name='Facturación'],[data-test-chart-name='Mi Matriz']) .ag-root {
  height: 100% !important;
}

/* ❌ Incorrecto — la coma hace que .hijo solo aplique al último selector */
[data-test-chart-name*='Gastos'],[data-test-chart-name='Facturación'] .ag-root { … }
```

Scroll horizontal: §4.2 — **nunca** `display: none` en `.ag-body-horizontal-scroll`.

Nombre del chart en `data-test-chart-name` debe coincidir con el título del chart en el setup.

### 12.6 JS — checklist por matriz nueva

En `config/tail_js_custom_extra.html`, para **cada** matriz nueva (IDs y storage keys **propios**):

| Paso | Qué | Notas |
|------|-----|-------|
| A | `isMiMatrizChart(chart)` | Por `data-test-chart-name` exacto o prefijo |
| B | Persistencia anchos | Clonar `initGastosColPersist` / `initFacturacionColPersist` — **otra** key `localStorage` / PUT |
| C | `sizeColumnsToFit` parcheado | Anti-snapback (como Gastos) |
| D | Buscador en cabecera | `place*SearchInHeader` — proxy, no mover input React |
| E | Anti-N/A | Incluir el chart en `isMatrixNaChart` **o** llamar `ensureMatrixNullBlank` desde el poll (mismo pipeline) |
| F | Tune scroll | `tuneAgGridScrollPerf(api)` al obtener el `api` (idempotente) |
| G | Poll 800 ms | Registrar init persistencia + `ensure*ColumnsFit` como Gastos/Facturación |

#### Anti-N/A (NULL → celda en blanco) — comportamiento canónico 2026-07-29

El plugin `ag-grid-table` pinta NULL numérico como `"N/A"`. Solución:

1. **`valueFormatter` envuelto** (`patchAgGridNullAsBlank`) — barato; AG Grid lo llama al virtualizar.
2. **Modo `light` (default):** sin `MutationObserver` ni barrido DOM en cada `bodyScroll`. Una pasada DOM al montar; poll 600 ms solo si aún hay N/A visibles.
3. **Modo `heavy` (rollback):** listeners de scroll + `MutationObserver` + barrido DOM (más fluido visual ante edge cases, más CPU en Retina).

| Control | Cómo |
|---------|------|
| Forzar heavy | `?_psna=heavy` o `window.__PS_MATRIX_NA_MODE='heavy'` + reload |
| Forzar light | `?_psna=light` (o default) |
| Modo activo | `window.__psMatrixNaModeActive` |

**No** añadir un observer nuevo “por si acaso” en matrices nuevas: enganchar al pipeline `isMatrixNaChart` / `ensureMatrixNullBlank`.

#### Tuning AG Grid (scroll)

`tuneAgGridScrollPerf(api)` aplica una vez por instancia:

- `rowBuffer: 6`
- `debounceVerticalScrollbar: true`
- `animateRows: false`

Rollback: `?_psgridtune=off` o `window.__PS_GRID_TUNE_DISABLED=true`.

#### Polls globales (todos los charts)

- Pausados si `document.hidden` (`psPollEnabled`).
- Rollback: `?_pspoll=always`.
- Poll anti-N/A: default 600 ms (`?_psnapoll=120` para el ritmo antiguo).

Tras cambiar `tail_js`: **reiniciar** contenedor `superset` (caché Jinja).

### 12.7 Expectativa de fluidez (Chrome vs PBI)

| Entorno | Qué esperar |
|---------|-------------|
| Cursor browser (DPR 1) | Más fluido — no usar como única prueba |
| Chrome Mac Retina (DPR 2) | Scroll más pesado; normal en AG Grid DOM |
| Power BI | Motor propio, no comparable 1:1 |

Medir en Chrome: `({ dpr: devicePixelRatio, w: innerWidth, h: innerHeight })` (antes: `allow pasting` en consola).

Si hace falta sensación “casi instantánea” con cientos/miles de filas: **paginación** o filtro previo — no más workers Gunicorn.

### 12.8 Checklist de entrega (matriz nueva)

- [ ] `bi_mv_<slug>` + `bi_v_<slug>` + índices + COMMENT
- [ ] REFRESH en workflow **004**
- [ ] `apply-bi-views.sh` aplicado y verificado en Analytics DB
- [ ] `_month_pivot_params` / params + dataset + pestaña en setup
- [ ] Filtros nativos `chartsInScope` actualizados
- [ ] CSS `:is(...)` altura + scroll H condicional
- [ ] JS: detector, persistencia (keys propias), buscador, anti-N/A compartido, `tuneAgGridScrollPerf`
- [ ] Pull UI → commit → push `gitea` → regenerar setup → restart si cambió `tail_js`
- [ ] Probar en **Chrome** (no solo Cursor): scroll V/H, sin flash N/A, buscador, totales, filtros
- [ ] Documentar chart en §1 inventario de esta guía

### 12.9 Mapa rápido de funciones (código)

| Función / símbolo | Rol |
|-------------------|-----|
| `_month_pivot_params` | Params Python canónicos meses |
| `gastos_unidad_params` / `facturacion_matriz_params` | Wrappers Gastos / Facturación |
| `isGastosChart` / `isFacturacionMatrixChart` | Detectores |
| `isMatrixNaChart` / `ensureMatrixNullBlank` | Anti-N/A compartido |
| `getMatrixNaMode` / `attachMatrixNaScrollGuards` | light vs heavy |
| `tuneAgGridScrollPerf` | rowBuffer / debounce / animateRows |
| `psPollEnabled` / `psNaPollMs` | Polls pausables / ritmo N/A |
| `initGastosColPersist` / `initFacturacionColPersist` | Anchos + anti-snapback |
| `placeGastosSearchInHeader` / `placeFacturacionSearchInHeader` | Buscador |

---

## 13. Fuente de verdad

| Área | Fuente |
|------|--------|
| Params, layout, CSS, owners | `scripts/setup-superset-planificacion.py` |
| Runtime AG Grid | `config/tail_js_custom_extra.html` |
| Feature flags | `config/superset_config.py` |
| Vistas BI / MVs | `scripts/sql/bi_dashboard_planificacion_views.sql` |
| REFRESH MVs | `src/workflows/004_sync_bc_to_ps_analytics.json` |
| Regla agentes | `.cursor/rules/superset-table-ag-grid.mdc` |
| Pull UI | `exports/superset-dashboard/README.md` + `superset-dashboard-ui-sync.mdc` |
| Matriz mes×dim | **Esta guía §12** |

Si código y esta guía divergen: comprobar navegador primero y actualizar **ambos**
en el mismo cambio.
