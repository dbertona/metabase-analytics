# Tablas AG Grid en Superset — Guía completa

> **Referencia rápida:** `.cursor/rules/superset-table-ag-grid.mdc`
> **Última actualización:** 2026-07-27
>
> **Patrón visual y funcional de referencia:** chart **Proyectos** (`id=21`).
> Toda tabla nueva creada por un agente debe reproducir este patrón completo,
> salvo que el usuario pida explícitamente una excepción.

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
        # Solo ano_mes (year/month en groupby rompían el layout). Orden cronológico vía JS.
        "groupby": ["ano_mes"],
        "metrics": [
            metric_sum("facturacion", "Fact."),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": [
            # Cronológico real (MM/YYYY como texto no ordena bien entre años)
            json.dumps(
                [
                    {
                        "expressionType": "SQL",
                        "sqlExpression": "to_date(ano_mes, 'MM/YYYY')",
                        "label": "orden_mes",
                    },
                    True,
                ],
                ensure_ascii=False,
            )
        ],
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
            "Fact.": {
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

> **Orden:** sin `order_by_cols`, Superset ordena por la 1ª métrica (Fact. DESC). Usar `to_date(ano_mes, 'MM/YYYY')`.

### Tabla de proyectos (con buscador)

```python
def mi_tabla_proyectos_params() -> dict:
    return {
        "adhoc_filters": dim_adhoc_filters("tipo"),
        "query_mode": "aggregate",
        "groupby": ["proyecto"],
        "metrics": [
            metric_sum("facturacion", "Fact."),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": ['["Fact.", false]'],
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
                # Una línea con elipsis; evita que nombres largos aumenten filas.
                "truncateLongCells": True,
                # Fallback nativo. El JS usa el espacio restante del viewport.
                "columnWidth": 280,
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
  font-size: 1.26em !important;
  border-bottom: 2px solid #d1d5db !important;
  box-shadow: none !important;
}

/* ══ CELDAS ══ */
[data-test-chart-name*='Nombre del chart'] td,
[data-test-chart-name*='Nombre del chart'] .ag-cell {
  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;
  font-size: 1.26em !important;
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

/* ══ TOTALES: ocultar «Resumen»/Summary + icono info ══ */
[data-test-chart-name*='Nombre del chart'] .ag-floating-bottom .ag-cell[col-id='ano_mes'],
[data-test-chart-name*='Nombre del chart'] .ag-floating-bottom .ag-cell[col-id='proyecto'] {
  visibility: hidden !important;
}
[data-test-chart-name*='Nombre del chart'] .ag-floating-bottom .anticon {
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

## 4. JavaScript canónico — `tail_js_custom_extra.html`

La configuración de Superset no cubre toda la UX requerida. El comportamiento
completo vive en `config/tail_js_custom_extra.html` y se ejecuta de forma
idempotente mientras React monta o recrea el chart.

### 4.1 Localizar el GridApi

`findAgGridApi()` recorre propiedades DOM y el árbol React Fiber. No se debe
suponer que `window.agGrid` o `window.echarts` existen. Cada inicialización se
marca en la instancia de API (`api.__psColPersistInit`) para no duplicar
listeners cuando el DOM cambia.

### 4.2 Distribución inicial de columnas

El patrón Proyectos no autosiza literalmente al texto más largo: un nombre
extenso podría expulsar las métricas fuera del card. La distribución estable es:

| Columna | Ancho inicial |
|---------|---------------|
| Dimensión textual (`proyecto`) | `max(280, viewport − métricas)` |
| Facturación | 110 px |
| Coste | 110 px |
| Margen | 100 px |

`getDefaultProyectosWidths()` calcula la dimensión textual con todo el espacio
restante. `sizeColumnsToFit()` se intercepta porque Superset lo invoca después
de cargar datos y, sin el parche, sobrescribe tanto el reparto inicial como un
resize manual.

Para otra tabla hay que adaptar:

- ID real de la columna textual.
- IDs/labels reales de las métricas (son los labels de `metrics`).
- Anchos compactos según formato y moneda.
- Clave de almacenamiento y chart ID; nunca reutilizar los de Proyectos.

### 4.3 Altura completa

`fixAgGridHeight()` propaga la altura del card hasta AG Grid. Si el buscador
nativo se oculta para integrarlo en la cabecera, Superset conserva un wrapper
con altura reducida. Es obligatorio devolverla:

```javascript
originalRow.parentElement.style.setProperty("height", "100%", "important");
```

La validación correcta no compara solo los cards. Debe comprobar que
`.ag-root-wrapper` de ambas tablas termina en el mismo `bottom`.

---

## 5. Buscador en la cabecera — patrón obligatorio

Con `include_search: True`, Superset crea una fila propia debajo del título.
El patrón canónico la elimina y coloca el buscador **inmediatamente a la
izquierda del menú vertical de tres puntos**, sin consumir otra línea.

### Por qué se usa un proxy

No se debe mover `#filter-text-box`: pertenece al árbol React y puede romperse
o volver a su posición en un rerender. `placeProyectosSearchInHeader()`:

1. Conserva el input real dentro de `.dropdown-controls-container`.
2. Crea un input proxy nativo con `aria-label`.
3. Lo inserta justo antes de `.header-controls`.
4. Reenvía `value` + evento `input` al input real mediante el setter nativo de
   `HTMLInputElement`.
5. Oculta la fila original y recupera su altura para el grid.
6. Busca el input real en cada pulsación; no conserva referencias React
   potencialmente obsoletas.

Al generalizarlo, la función debe aceptar el selector/chart ID y una clase
proxy única. Dos tablas no pueden compartir el mismo `id`, key de storage ni
referencia cerrada al input real.

---

## 6. Persistencia de anchos

### 6.1 Mismo navegador

Al finalizar un resize real (`columnResized`, `source="uiColumnResized"`):

1. `getColumnState()` obtiene `{colId, width}`.
2. Se guarda un mapa JSON en `localStorage`.
3. En la siguiente carga se aplica con `applyColumnState`.

Solo deben persistirse eventos del usuario. Guardar eventos de
`sizeColumnsToFit`, API o autosize genera bucles y sobrescribe preferencias.

### 6.2 Todos los dispositivos

El mismo mapa se guarda en `params.column_config[*].columnWidth` mediante:

1. `GET /api/v1/security/csrf_token/`
2. `GET /api/v1/chart/<id>`
3. `PUT /api/v1/chart/<id>` conservando el resto de `params`

Un navegador sin estado local obtiene los cuatro anchos desde
`GET /api/v1/chart/<id>`. El estado compartido solo se acepta si contiene todas
las columnas esperadas; un único `columnWidth` de fallback no cuenta como una
preferencia completa.

### 6.3 Seguridad y propietarios

El usuario que comparte el diseño necesita simultáneamente:

- Ser propietario del chart (`slice_user` / campo API `owners`).
- Permiso `can_write` sobre `Chart`.

En este dashboard:

- Chart Proyectos: `id=21`.
- Propietarios canónicos: Admin (`id=1`) y dbertona (`id=2`).
- dbertona usa el rol específico `PS_Chart_Editor`.
- **No** se concede `can_write` a `PS_Viewer`, porque permitiría editar a todos
  los usuarios de solo lectura.

El script `setup-superset-planificacion.py` debe conservar `owners=[1, 2]` al
regenerar Proyectos. Para otra tabla, definir explícitamente quién publica los
anchos; no copiar IDs de usuario entre entornos sin verificarlos.

### 6.4 Fallos que no deben ocultarse

La persistencia compartida solo está verificada si los logs muestran:

```text
GET /api/v1/security/csrf_token/ 200
GET /api/v1/chart/<id>            200
PUT /api/v1/chart/<id>            200
```

Un `403` significa falta de propiedad o `can_write`; no es un problema de
caché. Un `400` de CSRF exige revisar cookie segura, sesión y cabecera
`X-CSRFToken`.

---

## 7. Flujo obligatorio para crear una tabla nueva

1. Hacer pull de la UI antes de tocar/regenerar el dashboard:
   `python3 scripts/pull-superset-dashboard.py`.
2. Añadir dataset/vista BI canónica si corresponde.
3. Crear función de params con `viz_type="ag-grid-table"`,
   `truncateLongCells`, totales y formatos.
4. Añadir el chart a `setup-superset-planificacion.py` y al layout.
5. Aplicar el bloque CSS de §3.
6. Registrar la tabla en los helpers JS de altura y columnas.
7. Si tiene buscador, aplicar íntegramente §5.
8. Si admite resize, usar claves/IDs propios y aplicar §6.
9. Ejecutar el setup sin omitir el pull UI.
10. Reiniciar Superset si cambió la plantilla Jinja; el bind mount por sí solo
    no invalida la caché de plantillas.
11. Probar en navegador real según §9.

---

## 8. Selectores estables en Superset 6.x

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
| Chart por ID | `[data-test-chart-id='<id>']` |

> ⚠️ Superset 6.x usa `data-test` como atributo estable.
> Evitar selectores de clase como `.slice_header` (underscore) — solo válidos en Superset <3.

---

## 9. Validación obligatoria

La tabla no está terminada solo porque se renderice.

### 9.1 Navegador

- Todas las columnas previstas son visibles y no hay scroll horizontal
  accidental.
- La columna textual usa el espacio restante.
- El texto permanece en una línea con elipsis.
- Las métricas son compactas y legibles.
- El buscador está antes de ⋮, filtra y no crea una fila adicional.
- El grid utiliza toda la altura del card.
- Totales visibles; etiqueta «Resumen» oculta si así lo exige el diseño.
- Resize manual no hace *snapback*.
- Refresco conserva el ancho.
- Tras borrar `localStorage`, otro navegador recupera el ancho compartido.
- Consola sin errores nuevos.

### 9.2 Servidor y API

- `/analytics/health` devuelve `OK`.
- No hay respuestas 500 relacionadas en logs.
- El PUT del chart devuelve 200.
- Los cuatro `columnWidth` están presentes en `column_config`.
- Propietarios y rol editor tienen el alcance mínimo necesario.

### 9.3 Código y Git

- Validar sintaxis JavaScript del template.
- Validar sintaxis Python del setup.
- Revisar `git diff --check`.
- Commit y push a `gitea`.
- Aplicar al entorno después del commit, nunca antes.

---

## 10. Troubleshooting

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| Chart no aparece / tipo desconocido | `AG_GRID_TABLE_ENABLED: False` | Activar en `superset_config.py` + reiniciar |
| Tabla no llena el card | CSS no propaga height | Añadir bloque §3 + selector en `fixAgGridHeight` |
| Tabla queda más corta al ocultar buscador | Wrapper conserva altura calculada con controles | Aplicar `height:100%` al padre de `.dropdown-controls-container` |
| Buscador ocupa otra fila | Se usa el input nativo en su ubicación original | Crear proxy antes de `.header-controls` y ocultar la fila original |
| Buscador aparece pero no filtra | Proxy no usa el setter nativo / referencia React obsoleta | Resolver input real en cada evento y disparar `input` con bubbles |
| Resize de columnas no funciona | viz_type sigue siendo `"table"` | Cambiar a `"ag-grid-table"` |
| Resize vuelve inmediatamente | Superset ejecuta `sizeColumnsToFit()` | Interceptar la llamada y reaplicar estado guardado |
| Ancho se pierde al refrescar | Listener no filtra `uiColumnResized` o storage no se aplica | Revisar evento, key única y `applyColumnState` |
| Funciona local pero no en otro dispositivo | No se escribió/leyó `column_config` | Verificar secuencia GET/PUT y carga compartida |
| PUT chart devuelve 403 | Usuario no propietario o sin `can_write Chart` | Propietario + rol editor específico; no ampliar `PS_Viewer` |
| Código nuevo no aparece tras copiar template | Caché Jinja del proceso | Reiniciar contenedor Superset y recargar con cache-buster |
| Columnas con texto partido | Falta `truncateLongCells` | Configurarlo en cada columna y verificar `wrapText=false` |
| Menú ⋮ fuera del card | Padding derecho insuficiente | CSS `.chart-slice overflow: hidden` |

---

## 11. Fuente de verdad

| Área | Fuente |
|------|--------|
| Parámetros, propietarios y layout | `scripts/setup-superset-planificacion.py` |
| Comportamiento runtime AG Grid | `config/tail_js_custom_extra.html` |
| CSS del dashboard | `dashboard_css` generado por el setup |
| Regla breve para agentes | `.cursor/rules/superset-table-ag-grid.mdc` |
| Pull/snapshot UI | `exports/superset-dashboard/README.md` |

No copiar implementaciones antiguas desde commits o snippets. Si código y esta
guía divergen, comprobar primero el comportamiento en navegador y actualizar
ambos en el mismo cambio.
