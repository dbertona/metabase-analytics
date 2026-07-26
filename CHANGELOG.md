# Changelog — superset-analytics

## [Unreleased]

## [2026-07-26af] — Bordes en cada chart del Resumen

### Changed

- CSS: borde `1px #c5d0d3` + `border-radius: 6px` en
  `.dashboard-component-chart-holder` (KPI, tablas y gráficos).

## [2026-07-26ae] — Ocultar botón de filtro en todos los charts

### Changed

- CSS del dashboard Resumen: oculta badge/botón de filtros de cada chart
  (`.filter-counts` / `.filters-badge`); la barra de filtros nativos se mantiene.

## [2026-07-26ad] — Interfaz Superset en español

### Changed

- `BABEL_DEFAULT_LOCALE=es` + `LANGUAGES` (es/en) y locale de sesión forzado a `es`.
- Pack `messages.json` / `messages.mo` montados (imagen lean no los trae compilados).
- `COMMON_BOOTSTRAP_OVERRIDES_FUNC` inyecta el `language_pack` (si no, locale=es
  pero la UI React seguía en inglés hasta pedir el pack con sesión).

## [2026-07-26ac] — PS_Viewer solo lectura (sin Edit chart)

### Fixed

- Rol `PS_Viewer` sin `can_explore` / `can_slice` / writes (el menú “Edit chart”
  se muestra si hay `can_explore` en Superset, no solo `can_write` Chart).
- Altas Azure nuevas: `AUTH_USER_REGISTRATION_ROLE = PS_Viewer`.

## [2026-07-26ab] — Fix logout 404 por doble /analytics

### Fixed

- Logout del menú iba a `/analytics/analytics/logout/` (404 Superset): el JS
  `ensureAppRoot()` antepone APP_ROOT a `user_logout_url` que ya lo incluye.
- Middleware WSGI colapsa `/analytics/analytics/*` → `/analytics/*`.
- Patch en `tail_js_custom_extra.html` corrige hrefs/clicks con doble prefijo.

## [2026-07-26aa] — Dashboard header: usuario logado en lugar de owner

### Changed

- Patch frontend inyectado via `config/tail_js_custom_extra.html` montado en
  `tail_js_custom_extra.html` para que la barra del dashboard muestre el
  usuario autenticado en sesión en vez del propietario del dashboard.

## [2026-07-25aj] — Azure OAuth: metadata OIDC v2.0 (fix iss)

### Fixed

- `server_metadata_url` apunta a `/v2.0/.well-known/...` para alinear el
  claim `iss` del id_token (evita quedarse en login tras Azure).

## [2026-07-25ai] — OAuth Azure: redirect_uri absoluto bajo /analytics

### Fixed

- `redirect_uri` fijo a `/analytics/oauth-authorized/azure` para que el
  callback no caiga en el catch-all de Timesheet (AppError 404 + early-init).

## [2026-07-25ah] — Fix 404 logo / blank screen APP_ROOT

### Fixed

- Bug APP_ROOT (Superset 6.1): `PsAppInitializer` deshace el doble prefijo en
  `brandLogoUrl`/`APP_ICON` (el JS ya antepone `static_assets_prefix`).
- Revertido workaround `STATIC_ASSETS_PREFIX=/` que generaba `//static/...`
  (pantalla en blanco + CSP).

## [2026-07-25ag] — Fix OAuth state CSRF detrás de /analytics/

### Fixed

- Cookies de sesión `Path=/` + `Secure` para que Azure OAuth no falle con
  `mismatching_state` (dejaba al usuario colgado como `admin`).

## [2026-07-25af] — Nombre de recurso en barra (bc_resource)

### Added

- Al login Azure, lookup `bc_resource.name` por email y actualiza `first_name`/`last_name`
  (visible en la barra superior, estilo Timesheet).

## [2026-07-25ae] — SSO Microsoft (Azure AD) en Superset

### Added

- OAuth Entra ID (`AUTH_OAUTH`) con misma App Registration que Timesheet.
- Rol por defecto `Gamma` (lectura); Admin se asigna a mano.
- Secret vía `.env` (`AZURE_CLIENT_SECRET`) — no versionado.

## [2026-07-25] — Merge `feat/dashboard-resumen-fase3`

Cierre de rama: dashboard Resumen (tabs KPI/tablas + Gráficos), tabla Proyectos,
totales al pie, publicación `SUPERSET_APP_ROOT=/analytics` y sync UI antes de regenerar.
Detalle en entradas `2026-07-25*` de este changelog.

## [2026-07-25ad] — Publicación /analytics/ (apps.powersolution.es)

### Changed

- `SUPERSET_APP_ROOT=/analytics` + `ENABLE_PROXY_FIX` para path público.
- Scripts/README usan `…:8088/analytics` (NPM ya apunta a VM 100).

## [2026-07-25ac] — Pestaña Gráficos

### Changed

- Dashboard con tabs: **Resumen** (KPI + tablas) y **Gráficos** (Evolución + Margen).
- Filtros nativos con `tabsInScope` en ambas pestañas.
- Alturas tablas 45 (UI).

## [2026-07-25ab] — Proyectos al lado de Resumen + sin page size

### Changed

- Proyectos: sin `page_length` (oculta “Show entries”).
- Layout: Resumen mensual (4) | Proyectos (8) en la misma fila; altura 46.

## [2026-07-25aa] — Resumen mensual sin selector de page size

### Changed

- Resumen mensual: sin `page_length` (oculta “Show entries per page”).
- Altura Resumen mensual 46 (UI) + CSS ocultando controles de paginación.

## [2026-07-25z] — Totales al pie en Resumen mensual

### Changed

- Resumen mensual: `query_mode=aggregate`, `page_length=25`, altura 36.
- CSS sticky de fila Total también en Resumen mensual.

## [2026-07-25y] — Totales al pie en tabla Proyectos

### Changed

- Proyectos: `show_totals` + paginación cliente (`page_length=25`); altura 74.
- CSS sticky en fila summary/Total.

## [2026-07-25x] — Proyectos: excluir filas 0/0

### Changed

- `bi_v_resumen_proyectos`: `HAVING` facturación o coste ≠ 0 (filtro PBI «Filtro no es 0»).

## [2026-07-25w] — Tabla Proyectos (filtros PBI Operational + estado)

### Added

- Vista **`bi_v_resumen_proyectos`**: `tipo_proyecto = Operational` y
  `estado IN (Completed, Open, Planning)` — paridad Total Coste **4.350.042 €** / Margen **31,76 %**.
- Chart tabla **Proyectos** en dashboard Resumen.

## [2026-07-25v] — Cabeceras HEADER nativo (sin scroll markdown)

### Changed

- Obj/Plan: `MARKDOWN` → componente **`HEADER`** (el scroll venía del renderer markdown).

## [2026-07-25u] — Sync UI (KPI h=10) + cabeceras sin scroll

### Changed

- Incorpora alturas UI: KPI **10**, Probabilidad **36**.
- Cabeceras markdown altura **4** + `overflow-y: hidden` agresivo (scroll volvía con h=2).

## [2026-07-25t] — Centrado vertical real en cabeceras y KPI

### Changed

- Markdown y big_number: cadena flex `height:100%` + `justify-content/align-items: center`
  (antes los KPI tenían `align-items: flex-start`).

## [2026-07-25s] — Cabeceras Obj/Plan centradas sin scroll

### Changed

- CSS markdown: flex centrado vertical + `overflow: hidden` (Objetivos / Planificación).

## [2026-07-25r] — KPI sin icono filtro ni menú ⋮

### Changed

- CSS: oculta `slice_header` completo en tarjetas big_number (filtro + ⋮).

## [2026-07-25q] — Sin scrollbar en tarjetas KPI

### Changed

- CSS: `overflow: hidden` + ocultar scrollbar en big_number KPI.

## [2026-07-25p] — Etiqueta KPI Crecimiento → Δ %

### Changed

- Subheader / override de Obj·Plan Crecimiento: **Δ %**.

## [2026-07-25o] — Símbolo % en Margen y Crecimiento

### Changed

- KPIs Margen/Crecimiento: formato `.2%` (ratio sin `*100`) → p. ej. `17.43%`.

## [2026-07-25n] — Pull UI (altura KPI 15) + fuente −5%

### Changed

- Incorpora altura KPI **15** y Probabilidad **34** desde edits UI.
- Fuente KPI −5%: euros **22px**, % **16px**, etiquetas **15px**.

## [2026-07-25m] — KPI font-size +30%

### Changed

- Valores euros **18→23px**, % **13→17px**, etiquetas **12→16px** (CSS dashboard).

## [2026-07-25l] — Facturación/Beneficio ancho 2 (importes grandes)

### Changed

- COLUMN KPIs **6** + Probabilidad **6**: euros **2**, Margen/Crecimiento **1**.

## [2026-07-25k] — KPIs columna ancho 4 (antes 6)

### Changed

- COLUMN KPIs **4** (1 por tarjeta) + Probabilidad **8**.

## [2026-07-25j] — KPIs más estrechos (ancho 6; no altura)

### Changed

- COLUMN KPIs **6** + Probabilidad **6** (antes 7+5).
- Anchos por contenido: euros **2**, Margen/Crecimiento **1** (antes Crecimiento=2).
- Altura de tarjetas KPI sin cambios.

## [2026-07-25i] — Layout: KPIs en COLUMN (7) + Probabilidad (5)

### Changed

- **`build_layout`:** Obj + Plan agrupados en `COLUMN-KPIS` (ancho 7); **Facturación por
  Probabilidad** a la derecha (ancho 5, height 32 ≈ alto de las dos bandas).
- Resumen mensual pasa a fila completa (12) debajo.

## [2026-07-25h] — Docs/regla: pull UI obligatorio para agentes

### Added

- **`.cursor/rules/superset-dashboard-ui-sync.mdc`** (`alwaysApply: true`): todo agente debe
  hacer pull UI antes de regenerar el dashboard Resumen.
- Triggers / índice / `DOCUMENTATION_INDEX` / `FILTROS` / `exports/.../README` alineados.

## [2026-07-25g] — Pull UI Superset antes de regenerar dashboard

### Added

- **`scripts/pull-superset-dashboard.py`:** descarga dashboard Resumen + charts a
  `exports/superset-dashboard/latest/` y compara con `previous/`.
- **`setup-superset-planificacion.py`:** paso 0 = pull UI automático (aviso si hay edits
  manuales). `SKIP_SUPERSET_PULL=1` / `STRICT_UI_SYNC=1`.

## [2026-07-25f] — Facturación por Probabilidad = P+R (0→100 como PBI)

### Fixed

- **`bi_v_facturacion_probabilidad`:** suma P+R; `probability=0` se muestra como **100** (regla PBI).
  Bucket 100% PSI 2026 ≈ **5.707 mil €**.
- Chart Superset: `dist_bar` con valores en barra; entra en filtros Año/Empresa/Dept.

## [2026-07-25e] — Fix KPI Planificación Actual = P + R (paridad PBI)

### Fixed

- **`bi_v_planificacion_kpi`:** Planificación Actual y total Resumen PBI = **suma tipo P + tipo R**
  (PSI 2026: 3.685.687 + 2.688.861 = **6.374.548 €**). Ni híbrido por mes cerrado (~6,29 M)
  ni solo tipo P (3,69 M). Crecimiento vs Ingresos del año anterior (~18,07 %).
- Default filtro Empresas = PSI. Tabla Resumen: sin Tipo = P+R; con Tipo P|R = desglose.

## [2026-07-25d] — Fase 3: Dashboard Superset «Seguimiento Económico — Resumen»

### Changed

- **`scripts/setup-superset-planificacion.py`:**
  - Título dashboard → `Seguimiento Económico — Resumen` (slug `planificacion-ps-analytics` sin cambio).
  - Chart **Resumen mensual**: tabla agregada `ano_mes` + SUM Facturación/Coste + Margen % + totales (estilo PBI).
  - Persistencia de filtros/CSS y UUID de charts vía API (sin `docker exec`; regenerable desde Mac).
  - `SKIP_APPLY_BI_VIEWS=1` para omitir apply SQL cuando no hay cambios de vistas.
- Docs: README, filtros, fases seguimiento-económico → Fase 3 ✅.

### Validado (PSI 2026, live)

| Tipo | Facturación | Coste | vs PBI |
|------|-------------|-------|--------|
| P | 3.685.687 | 3.838.008 | exacto |
| R | 2.688.861 | 2.513.515 | Coste +582 € lag |

## [2026-07-25c] — Docs: alinear KPIs PBI con estado final CHANGELOG

### Changed

- **`ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`:** §7 y §9 actualizados — paridad exacta Factura/Coste P y Factura R; Coste R +582 € (lag). §9 marca el gap ~79k / hipótesis blank-lineType como archivo histórico.
- **`004_SYNC_BC_ANALYTICS.md`:** tabla de alineación PBI con targets 3.685.687 / 3.838.008 / 2.688.861 / 2.512.933.
- **`docs/seguimiento-economico/README.md`:** misma tabla de paridad; fase 2 marcada como paridad KPI Resumen cerrada.

## [2026-07-25b] — merge-safe.sh para cierre de rama

### Added

- **`scripts/merge-safe.sh`:** cierre auditado de ramas (`--no-ff` + push `gitea/main`).
  Esqueleto git portado de Apps; validaciones propias (JSON workflows, aviso SQL).
  Sin `npm lint/build` (este repo no tiene `package.json`).
- **`.cursor/rules/merge-command-workflow.mdc`:** apunta al script real y a post-merge n8n/SQL.

## [2026-07-25] — Partition overwrite en línea (PlanificacionMes / ExpedienteMes)

### Fixed

- **Huérfanos por cambio de `budgetDateMonth`:** el UPSERT incremental no borraba la PK antigua
  cuando BC movía la versión de presupuesto. Se elimina la necesidad de resync mensual completo.
- **`Prepare Expediente BC Requests`:** `fields` pasa de 3 timestamps a 1 (`lastModifiedDateTime`),
  evitando inflación Nx / OOM en el discovery (mismo criterio que PlanificacionMes).

### Changed

- **Workflow 004 — partition overwrite:** para `bc_job_planning_line` y `bc_expediente_mes`:
  1. Discovery por watermark (timestamp) detecta cambios.
  2. Se extraen particiones `(year, month)` tocadas.
  3. Snapshot OData completo: `$filter=year eq Y and month eq M`.
  4. `DELETE` de esas particiones en analytics + `INSERT` del snapshot (primer chunk).
  5. Watermark solo avanza con timestamp real de filas (no a `NOW()` vacío).
- Nodos nuevos: `Discover Partitions *`, `Prepare Snapshot *`, `BC API - * Snapshot`.

### Docs

- Retirada la recomendación de resync mensual DELETE+watermark como operación normal.
- Documentado el patrón partition overwrite en `004_SYNC_BC_ANALYTICS.md` y
  `ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`.

## [2026-07-24b] — Alineación completa Factura P / Coste P con PBI (PSI 2026)

### Fixed

- **`v_se_lineas_expedientes`**: eliminados CTEs `vigente` y JOIN asociado. La vista
  ahora filtra `bc_expediente_mes` con `budget_date_month = month AND budget_date_year = year`,
  replicando exactamente la lógica de PBI (cada mes usa su propia versión de presupuesto).
  Elimina el gap de ~60k € en Factura P de junio causado por el filtro de presupuesto vigente.

- **`v_se_lineas_planificacion`**: lógica híbrida para meses pasados mejorada.
  En lugar de `budget_date_month = month` (estricto), ahora usa
  `MAX(budget_date_month) <= month` como subconsulta correlacionada, permitiendo incluir
  proyectos Structure que tienen presupuesto en un mes anterior al planificado
  (e.g., `budget_date_month=5` en `month=6`). Cierra gap de ~54k € en Coste P (mayo/junio).
  - La rama de meses actuales/futuros no cambia: acepta todas las versiones y deduplication
    vía DISTINCT elimina repeticiones.
  - Se mantiene `NOT EXISTS (bc_meses_cerrados)` y `NOT EXISTS (Ingresos reales)`.

- **Datos huérfanos en `bc_expediente_mes`**: el sync incremental (UPSERT por PK) no borra
  registros cuando BC cambia `budgetDateMonth` (e.g., de 6 → 7). Se acumulaban filas
  huérfanas que inflaban Factura P ~60k €. Solución: DELETE + reset watermark + full resync.
  Proyectos afectados: `PSI-OT-23-2002`, `PSI-OT-23-2008`, `PSI-OT-24-2016`,
  `PSI-OT-24-2034`, `PSI-OT-25-2052` (eliminados correctamente tras resync).

- **Datos huérfanos en `bc_job_planning_line`**: misma causa raíz. Proyectos
  `PSI-OT-24-2032` (19.735 €) y `PSI-OT-26-2022` (4.675 €) permanecían con
  `budget_date_month=6` en junio cuando BC los había actualizado a budget=7.
  DELETE + reset watermark + resync corrige el gap de ~24k € en Factura P junio.

- **`Transform ExpedienteMes` (n8n 004)**: bug de doble-conteo por deduplicación
  incompleta. BC OData devuelve filas duplicadas (mismo invoice, distinto `lastModifiedDateTime`)
  cuando se consulta por ventanas de timestamp. La clave exacta (`exactKey`) incluye todos
  los campos incluyendo `invoice`, de forma que duplicados exactos se descartan antes de sumar.
  El `key` sin invoice agrega líneas genuinamente distintas del mismo expediente/mes.

### Changed

- **Resync completo `bc_expediente_mes` PSI**: DELETE de 3.156 filas + watermark
  `1900-01-01` + sync 004 → 2.947 filas reinsertadas desde BC. Elimina todos los huérfanos.

- **Resync completo `bc_job_planning_line` PSI**: DELETE de 34.134 filas + watermark
  `1900-01-01` + sync 004 → 1.966 filas reinsertadas desde BC. Elimina todos los huérfanos.

### KPIs PSI 2026 — Estado final (2026-07-24)

| Métrica | Analytics | PBI | Gap | Estado |
|---------|-----------|-----|-----|--------|
| Factura P total | 3.685.687 € | 3.685.687 € | 0 € | ✅ paridad exacta |
| Factura R total | 2.688.861 € | 2.688.861 € | 0 € | ✅ paridad exacta |
| Coste P total | 3.838.008 € | 3.838.008 € | 0 € | ✅ paridad exacta |
| Coste R | 2.513.515 € | 2.512.933 € | +582 € | ✅ lag de réplica |

Coste R: gap de +582 € atribuible a lag de réplica BC→analytics (registros modificados en BC
tras el último sync). No requiere acción técnica.

### Investigación técnica — Hallazgos de alineación P vs PBI

**Lógica PBI para `ExpedienteMes`:**
- Filtra por `budgetDateMonth = month` (cada mes usa su versión propia de presupuesto).
- Incluye filas negativas (correcciones/cancelaciones); el neto es el importe correcto.
- Agrupa por `(job, year, month, budgetDateMonth)` y suma neto incluyendo negativos.

**Lógica PBI para `PlanificacionMes` (meses pasados):**
- Incluye la última versión de presupuesto con `budgetDateMonth ≤ month`.
- Esto es relevante para proyectos Structure cuyo presupuesto no se actualiza cada mes.
- Incluye filas con `lineType = ''` (Both Budget & Billable) y `Billable`.
- Excluye meses con movimientos reales de tipo Ingresos (no muestra P si ya hay R).

**Causa raíz de huérfanos (patrón UPSERT) — mitigada 2026-07-25:**
El UPSERT por PK no borraba la versión antigua al cambiar `budgetDateMonth`.
Mitigación: **partition overwrite** en el 004 (discovery → snapshot por `(year,month)` →
DELETE partición + INSERT). Ver `004_SYNC_BC_ANALYTICS.md` § Partition overwrite.
Full wipe + watermark queda solo como recuperación excepcional.

## [2026-07-24] — Fix watermark n8n 004 + resync completo PSI

### Fixed

- **Bug watermark n8n 004** (`Compute now ISO / MovimientosProyectos`): el nodo avanzaba el
  watermark a `NOW()` aunque no trajera datos nuevos de BC. Movimientos de Resource (Mano de Obra)
  imputados en meses anteriores y no modificados desde entonces quedaban permanentemente fuera del
  sync incremental.
  - Fix: cuando `_maxRowTimestamp ≤ prevSync`, mantener `prevSync` como nuevo watermark en lugar de
    `new Date().toISOString()`. El watermark solo avanza cuando hay registros reales que lo respalden.
  - Archivo: `src/workflows/004_sync_bc_to_ps_analytics.json` — nodo `Compute now ISO (MovimientosProyectos)`.

### Changed

- Watermark `bc_job_ledger_entry_month` de PSI reseteado a `2023-01-01` para forzar resync completo
  del histórico.
- Post-resync PSI 2026: `bc_job_ledger_entry_month` pasa de 3.538 a **3.672 filas**; coste R sube
  de 1.497.530 € a **2.513.515 €**; facturación R sube a **2.688.861 €** (paridad exacta con PBI).

### KPIs PSI 2026 post-resync (jul 2026)

| Métrica | Analytics | PBI | Estado |
|---------|-----------|-----|--------|
| Facturación R | 2.688.861 € | 2.688.861 € | ✅ paridad exacta |
| Coste R | 2.513.515 € | 2.381.218 € | ⚠️ diferencia por diseño (ver abajo) |
| Facturación P | 3.695.962 € | ~3.696k € | ✅ alineado |

## [2026-07-23] — Espejo SQL + vista `v_se_coste`

### Added

- Vista `v_se_coste`: capa Coste P/R independiente de `v_se_facturacion` (misma fórmula
  `se_weight_amount`, con `fuente` y `coste_raw` para alinear vs PBI sin tocar facturado).

### Changed

- `sql/views/seguimiento_economico_views.sql` regenerado desde BD live (VM 100):
  `v_se_lineas_movimientos` usa `bc_job_ledger_entry_month`; planificación excluye
  meses con Ingresos reales; incluye vistas fase 2 (expedientes, meses cerrados, KPIs).
- README y reglas: fuente de verdad SQL Analytics = `superset-analytics`.

## [2026-07-23] — Filtros KPI / Departamentos (Superset 6.1)

### Added

- Vista `bi_v_planificacion_kpi` con `department_code`, `facturacion_real_anterior` por dept y plan híbrido (meses cerrados = R).
- Documentación canónica de filtros: `docs/FILTROS_DASHBOARD_PLANIFICACION.md`.

### Fixed

- Filtro Departamento aplicable a tarjetas KPI (dataset unificado).
- Apply filters deshabilitado: dims expuestas vía `adhoc_filters` en KPI (`dim_adhoc_filters`).
- Modal de edición roto (`[untitled customization]`): IDs con prefijo `NATIVE_FILTER-`.
- `enableEmptyFilter: false` para no exigir valor en todos los filtros.

### Changed

- Upgrade runtime documentado: Apache Superset **6.1.0**.
- UX: se mantiene el botón **Apply filters** (sin auto-apply; no soportado de forma nativa).

### Regenerar

```bash
./scripts/apply-bi-views.sh
python3 scripts/setup-superset-planificacion.py
```
