# Tablas AG Grid en Superset — Guía operativa (agentes)

> **Regla breve (alwaysApply):** `.cursor/rules/superset-table-ag-grid.mdc`  
> **Última actualización:** 2026-07-28  
> **Patrón de referencia:** chart **Proyectos** (`id=21`) — copiar comportamiento completo, no solo el render.

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
- [ ] CSS altura completa + fuente (bloque §3)
- [ ] **NO** ocultar `.ag-body-horizontal-scroll` (§3.1)
- [ ] JS: IDs/claves propios (no reutilizar Proyectos/Gastos)
- [ ] Buscador en cabecera (si `include_search`)
- [ ] Interceptar `sizeColumnsToFit` (evitar snapback)
- [ ] Pull UI → commit → push → regenerar → probar

---

## 1. Inventario actual (no reinventar)

| Chart | ID típico | Pestaña | Columnas | Buscador | Notas |
|-------|-----------|---------|----------|:--------:|-------|
| Resumen mensual | 17 | Resumen | `ano_mes` + 3 métricas | No | Encaja casi siempre; orden cronológico vía SQL/JS |
| Proyectos | 21 | Resumen | `proyecto` + 3 métricas | Sí | **Patrón canónico** de UX |
| Gastos | 22 | Unidad | concepto + 12 meses + Total | Sí | Muchas columnas → **scroll horizontal real** si no caben |
| Facturación | (nuevo) | Facturación | Encabezado + 12 meses + Total | Sí | Misma matriz que Gastos; filtros Operational + estados |

Si el usuario pide “otra tabla como Proyectos”, clonar el patrón Proyectos.
Si pide “matriz mes a mes”, mirar Gastos (pinned Total, anchos por mes, scroll).

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

---

## 11. Fuente de verdad

| Área | Fuente |
|------|--------|
| Params, layout, CSS, owners | `scripts/setup-superset-planificacion.py` |
| Runtime AG Grid | `config/tail_js_custom_extra.html` |
| Feature flags | `config/superset_config.py` |
| Vistas BI | `scripts/sql/bi_dashboard_planificacion_views.sql` |
| Regla agentes | `.cursor/rules/superset-table-ag-grid.mdc` |
| Pull UI | `exports/superset-dashboard/README.md` + `superset-dashboard-ui-sync.mdc` |

Si código y esta guía divergen: comprobar navegador primero y actualizar **ambos**
en el mismo cambio.
