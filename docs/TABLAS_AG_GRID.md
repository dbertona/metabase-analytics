# Tablas AG Grid en Superset — Guía completa

> **Referencia rápida:** `.cursor/rules/superset-table-ag-grid.mdc`
> **Última actualización:** 2026-07-26

---

## ¿Qué es Table V2 (AG Grid)?

Superset ofrece dos tipos de tabla:

| Tipo | `viz_type` | Resize columnas | Buscador integrado | Totales |
|------|-----------|:--------------:|:------------------:|:-------:|
| Table (legacy) | `table` | ❌ | ❌ | ✅ |
| Table V2 (AG Grid) | `ag-grid-table` | ✅ | ✅ | ✅ |

Las tablas «Resumen mensual» y «Proyectos» del dashboard de Seguimiento
Económico usan **AG Grid** desde 2026-07-26.

---

## 1. Activar el feature flag

En `config/superset_config.py`:

```python
FEATURE_FLAGS = {
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "AG_GRID_TABLE_ENABLED": True,   # ← obligatorio para ag-grid-table
}
```

Reiniciar el contenedor tras el cambio:
```bash
docker restart superset
```

---

## 2. Parámetros Python completos

### Tabla de agregados (tipo «Resumen mensual»)

```python
def mi_tabla_mensual_params() -> dict:
    return {
        "adhoc_filters": dim_adhoc_filters("tipo"),   # filtros cross-filter
        "query_mode": "aggregate",
        "groupby": ["ano_mes"],
        "metrics": [
            metric_sum("facturacion", "Facturación"),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": ['["ano_mes", true]'],
        "row_limit": 1000,
        "server_pagination": False,
        "show_totals": True,
        "include_search": False,      # sin buscador para tablas cortas
        "show_cell_bars": False,
        "color_pn": False,
        "align_pn": False,
        "table_timestamp_format": "smart_date",
        "column_config": {
            "ano_mes": {"customColumnName": "Año/Mes"},
            "Facturación": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Coste": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Margen %": {
                "d3NumberFormat": ".2f",
                "showCellBars": False,
            },
        },
    }
```

### Tabla de proyectos (con buscador)

```python
def mi_tabla_proyectos_params() -> dict:
    return {
        "adhoc_filters": dim_adhoc_filters("tipo"),
        "query_mode": "aggregate",
        "groupby": ["proyecto"],
        "metrics": [
            metric_sum("facturacion", "Facturación"),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": ['["Facturación", false]'],
        "row_limit": 5000,
        "server_pagination": False,
        "show_totals": True,
        "include_search": True,       # ← activa buscador AG Grid
        "show_cell_bars": False,
        "color_pn": True,
        "align_pn": False,
        "table_timestamp_format": "smart_date",
        "column_config": {
            "proyecto": {
                "customColumnName": "Proyectos",
                # Sin columnWidth: auto-size al contenido (tail_js autoSizeAgGridColumns)
            },
            "Facturación": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Coste": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Margen %": {
                "d3NumberFormat": ".2f",
                "showCellBars": False,
            },
        },
    }
```

En `charts_config`:
```python
("Resumen mensual", "table",    evo_ds,  "ag-grid-table", mi_tabla_mensual_params()),
("Proyectos",       "projects", proy_ds, "ag-grid-table", mi_tabla_proyectos_params()),
```

---

## 3. CSS del dashboard

El CSS se inyecta en `dashboard_css` dentro del script Python.
El bloque canónico para cualquier tabla AG Grid:

```css
/* ══ CABECERAS ══ */
[data-test-chart-name*='Nombre del chart'] thead th,
[data-test-chart-name*='Nombre del chart'] .ag-header-cell {
  white-space: nowrap !important;
  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;
  font-size: 1.33em !important;
  border-bottom: 2px solid #d1d5db !important;
  box-shadow: none !important;
}

/* ══ CELDAS ══ */
[data-test-chart-name*='Nombre del chart'] td,
[data-test-chart-name*='Nombre del chart'] .ag-cell {
  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;
  font-size: 1.33em !important;
}

/* ══ OCULTAR PAGINACIÓN Y BARRAS ══ */
[data-test-chart-name*='Nombre del chart'] .dt-length,
[data-test-chart-name*='Nombre del chart'] .dataTables_length,
[data-test-chart-name*='Nombre del chart'] .ant-pagination,
[data-test-chart-name*='Nombre del chart'] .pagination-container,
[data-test-chart-name*='Nombre del chart'] .row-count-container,
[data-test-chart-name*='Nombre del chart'] .cell-bar,
[data-test-chart-name*='Nombre del chart'] .cell-bars {
  display: none !important;
}

/* ══ ALTURA COMPLETA DEL CARD ══
   Paso 1: .chart-slice en flexbox columna para que .slice_container
           tome todo el espacio tras el header.
*/
[data-test-chart-name*='Nombre del chart'] .chart-slice {
  display: flex !important;
  flex-direction: column !important;
  height: 100% !important;
  overflow: hidden !important;
}
[data-test-chart-name*='Nombre del chart'] .slice_container {
  flex: 1 1 auto !important;
  min-height: 0 !important;
  overflow: hidden !important;
}
[data-test-chart-name*='Nombre del chart'] .chart-container,
[data-test-chart-name*='Nombre del chart'] .slice_container > div {
  height: 100% !important;
}
[data-test-chart-name*='Nombre del chart'] [class*='ag-theme'],
[data-test-chart-name*='Nombre del chart'] .ag-root-wrapper,
[data-test-chart-name*='Nombre del chart'] .ag-root-wrapper-body,
[data-test-chart-name*='Nombre del chart'] .ag-root {
  height: 100% !important;
  flex: 1 1 auto !important;
}
```

> **Por qué el CSS no es suficiente solo:**
> Superset/React puede poner `style="height: auto"` inline en algunos
> contenedores, ganando al `!important` del CSS. El JS `fixAgGridHeight`
> (ver §4) resuelve eso calculando píxeles exactos.

---

## 4. JavaScript — `fixAgGridHeight` + `autoSizeAgGridColumns`

Ubicado en `config/tail_js_custom_extra.html`. Se ejecuta cada 1.5 s.

Ambas funciones usan el array compartido `AG_GRID_CHART_SELECTORS`.

### Altura (`fixAgGridHeight`)

1. Para cada selector, localiza el chart holder.
2. Calcula `alturaDisponible = alturaHolder − alturaHeader − 8px`.
3. Si el valor cambió >4px, aplica `style.setProperty("height", Npx, "important")`
   en `.slice_container` y en el div `[class*="ag-theme"]`.

### Ancho de columnas (`autoSizeAgGridColumns`)

1. Localiza el `GridApi` de AG Grid caminando el árbol React (fiber).
2. Llama a `api.autoSizeAllColumns(false)` (incluye cabecera en el cálculo).
3. Guarda una huella del contenido (`data-ps-autosize-fp`) para no re-autosize
   en cada tick si los datos no han cambiado (filtros / refresh sí la invalidan).

**No** fijar `columnWidth` en `column_config` si quieres auto-size: el ancho fijo
de Superset pelearía con la API.

**Añadir una tabla nueva:**
```javascript
var AG_GRID_CHART_SELECTORS = [
  "[data-test-chart-name*='Resumen mensual']",
  "[data-test-chart-name*='Proyectos']",
  "[data-test-chart-name*='Nueva Tabla']",  // ← añadir aquí
];
```

---

## 5. Buscador junto al título — `moveProyectosSearchBesideTitle`

Por defecto el buscador AG Grid aparece debajo del header (a la derecha).
Para moverlo al lado del título del chart se usa un **input proxy nativo**
(no se mueve el nodo React porque React lo resetearía en el siguiente render).

**Cómo funciona:**
1. Localiza `#filter-text-box` (el input real de AG Grid).
2. Crea un `<input class="ps-search-proxy">` y lo inserta tras `.header-title`.
3. Oculta `.dropdown-controls-container` (contenedor original del buscador).
4. Reenvía eventos `input` del proxy al input real usando
   `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set`.

**Añadir una tabla nueva con buscador:**
```javascript
var charts = document.querySelectorAll(
  "[data-test-chart-name*='Proyectos'], [data-test-chart-name*='Nueva Tabla']"
);
```

---

## 6. Flujo completo para una tabla nueva

```
1. Añadir función de params en setup-superset-planificacion.py
2. Añadir entrada en charts_config con viz_type="ag-grid-table"
3. Copiar bloque CSS (§3) sustituyendo 'Nombre del chart'
4. Añadir selector en fixAgGridHeight (§4)
5. Si lleva buscador: añadir selector en moveProyectosSearchBesideTitle (§5)
6. Ejecutar: python3 scripts/setup-superset-planificacion.py
7. Verificar en http://192.168.36.100:8088/analytics/dashboard/planificacion-ps-analytics/
```

---

## 7. Selectores CSS clave en Superset 6.x

| Elemento | Selector |
|----------|---------|
| Card del chart (con nombre) | `[data-test-chart-name*='Nombre']` |
| Header del chart | `[data-test='slice-header']` |
| Título editable | `.header-title`, `.editable-title` |
| Controles (⋮) | `.header-controls` |
| Contenedor principal | `.slice_container` |
| Wrapper AG Grid | `[class*='ag-theme']` |
| Root AG Grid | `.ag-root-wrapper`, `.ag-root` |
| Buscador AG Grid | `#filter-text-box`, `.dropdown-controls-container` |

> ⚠️ Superset 6.x usa `data-test` como atributo estable.
> Evitar selectores de clase como `.slice_header` (underscore) — solo válidos en Superset <3.

---

## 8. Troubleshooting

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| Chart no aparece / tipo desconocido | `AG_GRID_TABLE_ENABLED: False` | Activar en `superset_config.py` + reiniciar |
| Tabla no llena el card | CSS no propaga height | Añadir bloque §3 + selector en `fixAgGridHeight` |
| Buscador no aparece junto al título | Selector no registrado | Añadir en `moveProyectosSearchBesideTitle` |
| Resize de columnas no funciona | viz_type sigue siendo `"table"` | Cambiar a `"ag-grid-table"` |
| Columnas con texto partido | Falta `white-space: nowrap` en `thead th` | Añadir CSS de cabeceras |
| Menú ⋮ fuera del card | Padding derecho insuficiente | CSS `.chart-slice overflow: hidden` |
