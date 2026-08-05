# Changelog — superset-analytics

## [Unreleased]

## [2026-08-05] — Movimientos: partition overwrite por cierre de mes (health 021)

### Fixed
- Health check 021 `tipo_r_sum` PSI: BC 2.724.184,04 vs Analytics 2.688.861,29
  (Δ 35.322,75). Causa: Ingresos de jun-2026 “aparecieron” en
  `MovimientosProyectosMes` al cerrar el mes (timestamps
  `monthClosingLastModifiedDateTime` / `jobLastModifiedDateTime` en ago-2026)
  sin actualizar `lastModifiedDateTime` del movimiento → el sync incremental
  del 004 no los pedía.
- Upsert quirúrgico en Analytics de 6 PKs jun-2026 (facturas + abonos
  PSI-OT-25-2053/2048/2018/2008, PSI-OT-24-2033, PSI-OT-23-2017) → paridad
  exacta `tipo_r_sum` = 2.724.184,04.

### Changed
- Workflow 004 `job_ledger_entry_month`: mismo patrón que PlanificacionMes —
  discovery por `lastModifiedDateTime` **+** `jobLastModifiedDateTime` **+**
  `monthClosingLastModifiedDateTime` → particiones year|month → snapshot OData
  del mes → DELETE+INSERT (sin inflación 3×: discovery no suma importes).

### Docs
- `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md`
- `docs/HEALTH_CHECK_021.md`

## [2026-08-04c] — ExpedienteMes: `job_unit_no` (evitar colapsar unidades con mismo invoice)

### Fixed
- Dos unidades del mismo job-mes pueden compartir el mismo Planned Amount
  (ej. PSI-OT-25-2005 / 2026-06: unidades 04 y 05 → 16.758,45 cada una).
  El `exactKey` / `DISTINCT ON (…, invoice)` descartaba una → total 22.344,61
  en vez de **39.103,06**.
- Columna `job_unit_no` en `bc_expediente_mes` (PK ampliada).
- Workflow 004: OData `jobUnitNo` → `job_unit_no` en `$select`, Transform
  (`exactKey` + clave de agregación) y Upsert (partition overwrite intacto).
- `v_se_lineas_expedientes`: Distinct incluye `job_unit_no`; columna expuesta
  para drill-down. `v_se_facturacion` suma todas las filas (UNION por nombres).

### Docs
- `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md`
- `docs/shared/analytics/ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`
- Migración: `sql/tables/bc_expediente_mes_job_unit_no.sql`

## [2026-08-04b] — Fix: historico_planificacion_mes particiones estáticas (sin Discovery)

### Fixed
- Causa raíz del `Invalid string length` / OOM: la fase **Discovery** paginaba
  TODOS los cambios del delta (42k+ filas tras modificación masiva en BC el
  2026-08-03) solo para descubrir year|month → V8 heap explotaba →
  `continueOnFail` silenciaba → watermark avanzaba sin escribir filas.
- Rediseño profesional: **eliminar Discovery**. `Prepare` genera particiones
  year|month estáticas (sinceYear..untilYear × 12 meses) con filtro
  `lastModifiedDateTime ge watermark` en cada Snapshot.
  - Partición vacía → 0 filas, ~100ms
  - Partición con cambios → volumen acotado por mes (~cientos/miles filas)
  - Inmune a modificaciones masivas
- `Split Historico Partitions` (batchSize=1) + `Loop Feedback Historico`
  (siempre 1 item) para avanzar el loop aunque Transform/Upsert den 0 filas.
  ⚠️ SplitInBatches v3: `out0=done`, `out1=loop` (invertido respecto a v1).
- `Compute now ISO`: watermark = `NOW()-5min` (buffer clock skew); ya no
  depende de `_maxRowTimestamp` del Discover.
- Nodos Discovery antiguos deshabilitados (`[DISABLED]`).
- Watermark Iberia reseteado a 2026-07-27 (antes de la masa) para re-sync.

## [2026-08-04] — Fix: historico_planificacion_mes partición year|month (Invalid string length)

### Fixed
- Primer intento (Discovery + Snapshot + Split). Insuficiente ante delta masivo:
  Discovery seguía paginando todo el delta. Sustituido por `[2026-08-04b]`.
- Liberados 3 mutex `running` huérfanos Iberia (ids 20187, 20201, 20209).

## [2026-07-31c] — Fix: historico_planificacion_mes Invalid string length

### Fixed
- `Prepare HistoricoPlanificacion BC Requests`: reducido `fields` de 3 a 1
  (`["lastModifiedDateTime"]` en vez de los 3 campos `lastModifiedDateTime /
  jobLastModifiedDateTime / monthClosingLastModifiedDateTime`). Los 3 campos
  generaban 3 requests HTTP con el mismo dataset → `Transform` acumulaba 3× las filas
  → la string V8 excedía el límite → `Invalid string length` en producción.
  Mismo fix que Bug 1/Bug 5 aplicados previamente a `PlanificacionMes` y
  `MovimientosProyectos`. Desplegado en n8n prod (d1f7647e114a486e, 2026-07-31 14:05).

## [2026-07-31b] — Mano de Obra: flags mes cerrado en la vista

### Added
- `bi_mv_mano_obra` / `bi_v_mano_obra`: columnas `m01_closed`…`m12_closed`
  (boolean) desde `bc_meses_cerrados` join por `empresa`+`job`+`year`.
  Fuente única para pintar celdas de mes cerrado en Apps (Seguimiento Económico)
  y en cualquier consumidor de la vista.

## [2026-07-31] — Mano de Obra: filtro CA + orden pestañas + tabla plana (árbol AG Grid descartado)

### Fixed
- `bi_v_mano_obra`: excluir "Trabajos relacionados" (solo CA vacío o `Mano de Obra%`) —
  paridad con PBI (antes 1.310.025 € vs 1.283.273,995 € PBI).
- Orden de pestañas del dashboard Resumen: Resumen → Facturación → Unidad → Gastos →
  Mano de Obra → Gráficos.

### Changed
- Se descartó la jerarquía Proyecto→Recurso vía AG Grid Community tras varios intentos
  (DOM renderer, SQL nivel/sort_key, external filter API, `setRowHeight`) por resultar
  inestable en producción (cuelgues, sin expand/collapse funcional).
- `bi_v_mano_obra` / `bi_mv_mano_obra` vuelve a filas planas (proyecto + recurso).
- Chart Superset "Mano de Obra": tabla plana Proyecto/Recurso × meses (sin árbol).
- `tail_js_custom_extra.html`: eliminada la lógica de árbol (`moToggle`,
  `moApplyRowClasses`, CSS de sangrado); mantiene solo persistencia de columnas.

### Next
- La jerarquía Proyecto→Recurso se construirá en un módulo React dedicado en
  `power-solution-apps` (TanStack Table, expand/collapse nativo) consumiendo
  `bi_v_mano_obra` vía un endpoint propio del backend (decisión de arquitectura
  2026-07-31: Superset se mantiene para el resto del dashboard).

## [2026-07-30d] — Pestaña Mano de Obra (matriz coste Resource)

### Added
- Vista `bi_v_mano_obra` / MV `bi_mv_mano_obra`: coste `Operational` +
  `type_line = Resource` (mano de obra), `Completed`/`Open`/`Planning`,
  total>0 (`scripts/sql/bi_dashboard_planificacion_views.sql`).
- Pestaña **Mano de Obra** en el dashboard Resumen (después de Gastos):
  chart AG Grid matriz mes×proyecto (`scripts/setup-superset-planificacion.py`).
- JS propio en `config/tail_js_custom_extra.html` (anti-N/A, scroll,
  persistencia) siguiendo el patrón de Gastos/Facturación.
- REFRESH de `bi_mv_mano_obra` añadido al workflow n8n **004**
  (`src/workflows/004_sync_bc_to_ps_analytics.json`) y a
  `scripts/apply-bi-views.sh`.
- Doc: `docs/TABLAS_AG_GRID.md` — fila `bi_v_mano_obra` en la tabla de
  vistas matriz mes×dim.

## [2026-07-30c] — Health Check 021 Analytics vs BC

### Added
- Workflow n8n **021** (`src/workflows/021_health_check_analytics_bc.json`):
  reconciliación diaria BC ↔ Analytics.
- Tabla `analytics_health_log` (`sql/tables/analytics_health_log.sql`).
- Email alerta vía Outlook noreply → `dbertona@powersolution.es` si hay diff.
- Schedule L–V 07:00 + webhook `POST /webhook/analytics-health-check`.
- Deploy: `./scripts/deploy-n8n-workflow-021.sh`
- Doc: `docs/HEALTH_CHECK_021.md`

### Fixed
- No comparar bruto `planificacionMes` vs `bc_job_planning_line` (falsos fail):
  PBI/Superset usan **Planificación Actual = P+R** (`v_se_facturacion`).
  Checks: `tipo_r_sum`, meses cerrados (tolerancia), budget=0, freshness;
  `planificacion_actual_p_plus_r` solo como contexto.
- Email solo por `status='fail'` (dinero real, señal budget0, o >5% meses
  cerrados). Los `warn` (diferencias menores, p. ej. timing OData) quedan
  solo en `analytics_health_log` — evita fatiga de alarma.

## [2026-07-30b] — Fix paginación Transform MesesCerrados (workflow 004)

### Fixed
- **`Transform MesesCerrados`** en workflow n8n 004: solo procesaba la primera página
  OData de `mesesCerrados`, dejando `bc_meses_cerrados` incompleta tras re-sync.
  Causa: líneas `PP*`/`PY*` en la primera página provocaban que el resultado fuera
  vacío aunque existían más páginas con datos válidos.
- Corregido siguiendo el patrón de `Transform HistoricoPlanificacionMes`:
  acumula **todas** las páginas con `$input.all()` antes de filtrar.
- Efecto: `bc_meses_cerrados` ahora se carga completa para todas las empresas
  (Lab incluido), eliminando la discrepancia Tipo P Analytics vs PBI causada por
  líneas de plan en meses cerrados que no eran excluidas correctamente.

### Context
- Investigación reveló que la discrepancia Planificado Lab (Analytics 857 k€ vs
  PBI 1.231 k€) no era datos malos en BC, sino planificación válida sin versionar
  (`budgetDateYear=0`) en meses ya cerrados con ingresos reales.
- El usuario corrigió BC (eliminó líneas ene-jun, versionó Jul-Dic con `budgetDateYear=2026`).
- Analytics resincronizado: paridad exacta `v_se_facturacion` Tipo P = plan bruto BC.

## [2026-07-30] — Pestaña Gastos (Encabezado × mes) + paridad PBI

### Added
- Pestaña **Gastos** en dashboard `planificacion-ps-analytics`: matriz AG Grid
  Encabezado × meses 01–12 + Total (coste), dataset `bi_v_gastos` / `bi_mv_gastos`.
- Chart **Unidad** (antes «Gastos» en pestaña Unidad): concepto analítico × mes.
- REFRESH `bi_mv_gastos` en workflow **004**.

### Fixed
- Filtros PBI en SQL: Operational + Completed/Open/Planning + coste > 0 +
  **excl. `type_line = Resource`** (evitaba inflar ~2,4 M€ vs PBI ~1,98 M€ PSI 2026).
- Lazy-load JS: chart id 22 mapeado a pestaña Gastos (no Unidad).

### Docs
- `docs/TABLAS_AG_GRID.md`, `FILTROS_DASHBOARD_PLANIFICACION.md`,
  `seguimiento-economico/README.md`.

## [2026-07-29m] — Docs: receta matriz mes×dim (Gastos/Facturación)

- `docs/TABLAS_AG_GRID.md` **§12**: SQL MV, `_month_pivot_params`, CSS `:is`, JS
  (anti-N/A light, tune AG Grid, polls), checklist y mapa de funciones.
- Índice + regla `superset-table-ag-grid.mdc` apuntan a §12.

## [2026-07-29l] — Mano de Obra solo `type_line = Resource`

### Fixed
- `v_se_lineas_movimientos`: conceptos `Mano de Obra*` excluyen `G/L Account`
  (p. ej. nr `0000003` en PS Lab jun 2026 duplicaba Admin/Dirección/Oferta/…).
  Coste G/L de otros CA (p. ej. Structure sin depto) no se toca.

## [2026-07-29k] — Perf: tuning interno AG Grid (rowBuffer/debounce/animateRows)

- `tuneAgGridScrollPerf(api)`: `rowBuffer=6`, `debounceVerticalScrollbar=true`,
  `animateRows=false` en Proyectos, Gastos, Facturación y Resumen mensual.
- Aplicado una vez por instancia de grid (`api.__psScrollPerfTuned`), vía
  `api.setGridOption()` con fallback silencioso si la versión de AG Grid no lo soporta.
- Rollback: `?_psgridtune=off` o `window.__PS_GRID_TUNE_DISABLED=true`.

## [2026-07-29j] — Perf: pausar polls JS si pestaña oculta + anti-N/A más lento

- `psPollEnabled()`: los `setInterval` del dashboard no trabajan con `document.hidden`
  (Chrome Retina). Rollback: `?_pspoll=always` / `__PS_POLL_ALWAYS=true`.
- Poll anti-N/A: 120 ms → **600 ms**; en modo `light` deja de re-escanear si ya
  `ps-na-ready`. Rollback: `?_psnapoll=120` / `__PS_NA_POLL_MS=120`.

## [2026-07-29i] — Perf: anti-N/A Facturación/Gastos en modo light (reversible)

- Default `light`: solo `valueFormatter` + re-parche en carga de datos (sin
  `bodyScroll` / `MutationObserver` / barrido DOM en cada scroll).
- Rollback sin redeploy: `?_psna=heavy` o `window.__PS_MATRIX_NA_MODE='heavy'` + reload.
- Modo activo: `window.__psMatrixNaModeActive`.

## [2026-07-29h] — Perf: carga progresiva charts en Resumen (tail_js)

- Experimento en `config/tail_js_custom_extra.html`: prioriza KPIs (slices 9–16) y
  difiere charts pesados de Resumen (17, 20, 21) ~150 ms tras 6 KPIs permitidos.
- Otras pestañas (Unidad / Facturación / Gráficos) se cargan al montar la pestaña
  (Superset ya no pide sus `/chart/data` al abrir Resumen).
- Stats: `window.__psLazyTabStats` (`deferred`, `flushed`, `seenSids`).
- Verificado en navegador: `deferred=3`, `flushed.ResumenHeavy=3`, Facturación OK al
  cambiar de tab; dos oleadas `/chart/data` (~800 ms de separación).

## [2026-07-29g] — Perf: metadata Superset (WAL + StdOutEventLogger + Postgres)

- Diagnóstico: cuello de botella en `superset.db` (SQLite `journal_mode=delete` +
  `DBEventLogger` → tabla `logs` ~13k filas/24h), no en el volumen Analytics (~50k filas).
- **Fase A/B:** `PRAGMA journal_mode=WAL`, `SQLALCHEMY_ENGINE_OPTIONS` busy_timeout,
  `EVENT_LOGGER = StdOutEventLogger()` (Action Log UI deja de poblarse; eventos en
  `docker logs`).
- **Fase C:** base Postgres `superset_meta` en instancia `supabase-db` (VM 100);
  `SQLALCHEMY_DATABASE_URI` por defecto a esa DB; script
  `scripts/migrate-superset-metadata-to-postgres.py` (excluye `logs`/`query`).
- Rollback: `SUPERSET_DATABASE_URI=sqlite:////app/superset_home/superset.db.bak` +
  recreate; backups en VM 100 `backups/superset-pre-pg-migration-*.db`.
- Verificación navegador: dashboard Resumen OK; span `/chart/data` ~1.1 s (16 charts).

## [2026-07-29f] — Perf: materializar capas BI + REFRESH en sync 004

- `bi_v_planificacion_kpi`, `bi_v_evolucion_mensual`, `bi_v_facturacion_probabilidad`,
  `bi_v_resumen_proyectos`, `bi_v_unidad`, `bi_v_facturacion` → **MATERIALIZED VIEW**
  `bi_mv_*` + wrapper `bi_v_*` (Superset/RLS sin cambio de nombre).
- Workflow **004**: nodo `Refresh BI Materialized Views` tras `Compute Execution Summary`
  (antes de liberar mutex) + restore del payload de resumen.
- `scripts/apply-bi-views.sh`: destino remoto/DSN + `--refresh`.

## [2026-07-29e] — AG Grid: NULL de meses vacíos sin flash N/A

- Cause: plugin AG Grid de Superset formatea NULL numérico como `"N/A"` (`formatValue.ts`).
- `tail_js`: parche `valueFormatter` → `""` + clase `ps-na-pending` (opacity 0) hasta listo.
- Aplica a matrices **Facturación** y **Gastos** (mismo patrón).
- Scroll/virtualización: re-parche en `bodyScroll`/`viewportChanged` + MutationObserver
  (Superset restauraba el formatter al pintar filas nuevas → flash N/A al desplazarse).

## [2026-07-29d] — Perf Superset: workers + FileSystemCache + JIT

- `docker-compose.yml`: `SERVER_WORKER_AMOUNT=3`, `SERVER_THREADS_AMOUNT=20`, `GUNICORN_TIMEOUT=120` (antes 1 worker por defecto).
- `config/superset_config.py`: `CACHE_CONFIG` / `DATA_CACHE_CONFIG` / filter+explore con `FileSystemCache` bajo `/app/superset_home/cache` (TTL 5–10 min).
- Analytics DB (`postgres`): `jit_above_cost = 10000000` (antes 100000) — evita JIT en vistas `bi_v_*`/`v_se_*` con coste estimado alto y filas pocas (~50 ms ahorrados por query KPI).

## [2026-07-29c] — Fix altura AG Grid pestaña Unidad (Gastos)

### Fixed
- Selectores CSS `[Gastos],[Facturación] .hijo` solo aplicaban altura a Facturación
  (coma CSS). Gastos quedaba ~560 px con card vacío. Ahora `:is(Gastos, Facturación)`.

## [2026-07-29b] — Pestaña Facturación (matriz Encabezado × mes)

### Added
- Vista **`bi_v_facturacion`**: pivot facturado por encabezado × meses 01–12 + Total.
  Filtros PBI: Operational, estado Completed/Open/Planning, total > 0 (PP/PY ya en `v_se_*`).
- Pestaña **Facturación** en dashboard `planificacion-ps-analytics` (AG Grid, patrón Gastos).
- JS/CSS propios (`tail_js` + `dashboard_css`) con Encabezado, scroll y buscador en cabecera.

### Changed
- Filtros nativos Año/Empresa/Dept/Tipo/Proyectos incluyen la nueva pestaña.

## [2026-07-29] — Fix `v_se_lineas_expedientes` solo meses Open

### Fixed
- `v_se_lineas_expedientes`: filtro `month_closing_status = 'Open'` (+ Job no Completed/Lost).
  Antes `NOT IN ('Completed','Lost')` dejaba entrar meses **Close** (~735 k€ en 1-02/2026)
  y los sumaba al Tipo P junto al Real.

## [2026-07-29] — Cierre rama `feat/rls-projectteamfilter`

### Summary
- RLS por `projectteamfilter`: usuarios con flag BC solo ven proyectos de su `bc_job_team`.
- Filtro nativo **Planificado/Real** (`tipo_label`) en lugar de P/R.
- Tarjetas **Plan** KPI responden al filtro Tipo (grano dept×tipo); Objetivos solo en filas P.
- Tabla Proyectos ordenada por Margen % desc; etiquetas Probabilidad sin corte; sin banner RLS.

### Added
- Modo `project_team` en `resolve_user_scope()` / Jinja (`ps_row_filter`, `ps_team_jobs_sql`).
- `tipo_label` en vistas BI (evolución, resumen, unidad, KPI).

### Fixed
- Native filter Tipo ignorado en charts sin `tipo_label` en `adhoc_filters`.
- Plan · Facturación fijo en P+R (7.149.796 €) al filtrar Real.
- Scroll/corte de etiquetas en Facturación por Probabilidad.

### Changed
- `NATIVE_FILTER-TIPO`: nombre Planificado/Real; `chartsInScope` incluye Plan KPI (no Obj).

## [2026-07-28u] — Cierre rama `feat/rls-departamento-server-side`

### Summary
- RLS server-side por departamento en datasets BI (`ps_dept_filter` Jinja + SQL virtual).
- Simulación de usuario vía cookie firmada `ps_sim` y API `/api/v1/ps/simulate`.
- UI: banner de dept fijado, ocultar filtro Departamentos, sin bucle refresh/hang.
- Acceso navegador solo por DNS `apps.powersolution.es/analytics` (no IP LAN).
- Regla agente: verificación obligatoria en Browser MCP.

### Added
- `JINJA_CONTEXT_ADDONS` / `ps_dept_filter()` en `config/superset_config.py`.
- `patch_dataset_virtual_sql` + `DEPT_FILTERED_VIEWS` en setup dashboard.
- `.cursor/rules/00-BROWSER-VERIFY-MANDATORY.mdc`.

### Fixed
- Simulación respetada en RLS (antes admin/sim veía todos los depts).
- Bucle `location.replace` del guard de departamento.
- Hang «Loading filter values» por `MutationObserver` en attributes class/style.

## [2026-07-28t] — merge-safe: auto-borrar también `chore/*`

### Changed
- `delete_merged_branch` acepta `chore/*` (además de feat/fix/hotfix).

## [2026-07-28s] — Merge-safe borra la rama tras merge

### Changed
- `merge-safe.sh`: tras merge + push a `main`, elimina la rama `feat/*`|`fix/*`|`hotfix/*`
  en local, `gitea` y `origin` (si existe). Escape: `KEEP_BRANCH=1`.
- Reglas (`merge-command-workflow`, `git-workflow-automatic`, `sync-gitea-before-code`):
  obligatorio no declarar «rama cerrada» si la feature sigue viva.

## [2026-07-28] — Cierre rama `feat/simular-usuario-recursos`

### Summary
- Combo Admin/Alpha/PS_Testing para simular usuario; ámbito departamento por usuario.
- Dashboard chrome: navbar oculta, simulación en cabecera, botón Salir.
- Banda KPI/Prob compacta, max-width 1440 ultrawide, tipografía y espaciados afinados.
- Probabilidad: chart llena el card; altura sync UI (26); separación 12px vs tablas.
- Docs Query IDs AL del workflow 004 (ExpedienteMes QRY50215).

## [2026-07-28r] — Separación KPI ↔ tablas + sync Prob 26

### Changed
- Pull UI: Probabilidad height **28→26** (edit manual) incorporado al script.
- Margen superior **12px** en la fila Resumen/Proyectos (menos “pegado” a KPIs).

## [2026-07-28q] — KPI: menos hueco + etiquetas sin recorte

### Fixed
- Headers Objetivos/Planificación: height **3→2** (menos espacio vacío bajo el título).
- Cards KPI: height **7→8**, padding más bajo; etiquetas **11px** (1.077em recortaba).
- CSS: overflow visible en subheader + line-height compacto.

## [2026-07-28p] — KPI: etiquetas = fuente tablas

### Changed
- Etiquetas FACTURACIÓN/MARGEN/Δ%/BENEFICIO: **1.077em** (igual que celdas AG Grid
  Resumen/Proyectos). Números KPI sin cambio.

## [2026-07-28o] — Probabilidad: fuente −10%

### Changed
- Tipografía ECharts Probabilidad: factor **0.715 → 0.6435** (−10%).
- Sin regenerar layout (pull: divergencias solo de alias de nombres KPI).

## [2026-07-28n] — Probabilidad: chart llena el card

### Changed
- Pull UI previo: sin divergencias vs previous; altura Probabilidad **28** (sync script).
- ECharts `grid` más ajustado + CSS flex/`height:100%` para ocupar el contenedor.
- Margen inferior ~10px (padding + `grid.bottom`).

## [2026-07-28m] — KPI: etiquetas +15%

### Changed
- Solo títulos bajo el valor (FACTURACIÓN, MARGEN, Δ %, BENEFICIO): **8px → 9.2px**.
- Números KPI sin cambio (euros 14px / % 11px).

## [2026-07-28l] — Dashboard max-width 1440 (ultrawide)

### Changed
- Contenido del dashboard (header + grid) con `max-width: 1440px` centrado.
  En pantallas ≤1440 sigue al 100%; en ultrawide evita estirar tablas/KPI.
  Panel de filtros nativos queda fuera del techo (columna hermana).

## [2026-07-28k] — Probabilidad: fuente +10%

### Changed
- Tipografía ECharts de Facturación por Probabilidad: factor **0.65 → 0.715** (+10%).
- Título del chart Probabilidad: **12px → 13px**.

## [2026-07-28j] — Compactar banda KPI+Prob ~−35%

### Changed
- Layout superior: KPI height **10→7**, headers **4→3** (`SMALL_HEADER`), Probabilidad **34→22**.
- Tipografía KPI: euros **14px**, % **11px**, etiquetas **8px**; `header_font_size` 0.58 / subheader 0.4.
- Títulos de sección Objetivos/Planificación **12px**; título Probabilidad **12px**.
- `tail_js`: fuentes ECharts de Probabilidad a ~65% del tamaño de tablas.

## [2026-07-28i] — Probabilidad height 34 desde UI

### Changed

- Layout `Facturación por Probabilidad`: height **34** (pull UI Superset;
  antes 28 en script). Así no se pierde al regenerar el dashboard.

## [2026-07-28h] — Edición UI: resize KPIs/Probabilidad + Salir

### Fixed

- En **modo edición**, CSS deja visible el asa de resize (`react-resizable-handle`)
  en KPIs y Probabilidad (`overflow: visible`, z-index alto; drop zones del COLUMN
  no roban el ratón). Antes solo redimensionaban las tablas de abajo.
- En edición se muestra el menú ⋮ también en KPIs (Editar chart).
- Botón **Salir** en la cabecera del dashboard (navbar global oculta).

## [2026-07-28g] — Probabilidad: menos alto de card

### Changed

- Layout `Facturación por Probabilidad`: height **36 → 28** (alineado al alto de
  Objetivos + Planificación Actual; elimina el hueco blanco bajo el eje).

## [2026-07-28f] — Dashboard sin navbar + combo en cabecera

### Changed

- En rutas de dashboard se oculta la navbar global de Superset (logo / Paneles /
  idioma / Ajustes) — modo informe.
- El combo 🧪 de simulación de usuario se monta en la cabecera del dashboard
  (junto a usuario / «hace …»), no fixed sobre la navbar.

## [2026-07-28e] — Query IDs AL exactos en docs sync 004

### Fixed

- `ExpedienteMes` documentado como QRY**50229** (era `LoginCompany`); ID real
  **50215** (`PS_ExpedienteMes`).
- Tabla completa EntitySet ↔ Query AL del workflow 004 en
  `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md` y `docs/GUIA_COMPLETA_ANALYTICS.md`.
- Mapeo campos `ExpedienteMes` en `ANALYTICS_FACTURACION_PBI_ALIGNMENT.md`.

## [2026-07-28d] — Ámbito departamento (paridad PBI)

### Added

- API `GET /api/v1/ps/user-scope`: email efectivo → `bc_user_configuration.departamento`.
  Vacío o `999` = ver todos los departamentos; otro valor fuerza filtro nativo
  `NATIVE_FILTER-DEPT` (`department_code`).
- Al cargar el dashboard (y al cambiar el combo de simulación) se aplica el ámbito
  vía `native_filters` en la URL; banner informativo si hay departamento forzado.

### Changed

- La simulación de usuario ya no es solo identidad visual: el email simulado
  determina el ámbito de departamento (requiere Admin/Alpha/PS_Testing).

## [2026-07-28c] — Fix sync Departamento en ConfiguracionUsuarios

### Fixed

- Transform 004 leía solo `r.Departamento`; la API BC devuelve `departamento`
  (camelCase) → `bc_user_configuration.departamento` quedaba vacío.
- `$select` alineado a `departamento`; Transform acepta ambos casings.

## [2026-07-28b] — Rol PS_Testing para combo simulación

### Added

- Rol Superset `PS_Testing`: permite el combo de simulación de usuario sin
  ser Admin/Alpha (mismo patrón que Testing en Apps).
- Se crea solo al arrancar si no existe; asignado a `dbertona@powersolution.es`.

## [2026-07-28a] — Combo simular usuario (Admin/Alpha)

### Added

- Combo de recursos (como Apps) para simular el usuario mostrado en la barra.
  Solo **Admin/Alpha**; cambia el nombre visual, **no filtra** datos del dashboard.
- API `GET /api/v1/ps/resources` (bc_resource activos con email).
- Persistencia en `localStorage` (`psSimulatedUserEmail`).

## [2026-07-28] — Cierre rama `fix/scroll-horizontal-ag-grid`

### Fixed

- Scroll horizontal en grillas AG Grid (Resumen, Proyectos, Gastos): ya no se
  oculta la barra; aparece solo cuando el contenido supera el ancho del card.
  CSS: `overflow-x: auto` en viewports; se eliminó `display:none` de
  `.ag-body-horizontal-scroll`.

### Docs

- Guía operativa de tablas AG Grid reescrita para agentes
  (`docs/TABLAS_AG_GRID.md` §0 Receta + anti-patrones + scroll).
- Regla `.cursor/rules/superset-table-ag-grid.mdc` con prohibiciones explícitas
  y comandos con `SUPERSET_URL=…/analytics`.
- Índice compartido: Doc Router Analytics + URLs corregidas con `/analytics`.

## [2026-07-27g] — Cierre rama `fix/gastos-llenar-alto-disponible`

### Fixed

- Card **Gastos** (Unidad) alineado con Resumen: margen inferior ~8–9px
  midiendo `--ps-unidad-top` desde el chart-slice (no el holder).
- AG Grid rellena el card: `.dashboard-chart` en flex para eliminar el hueco
  blanco bajo la fila Total.

### Changed

- Fuente de grillas AG Grid: `1.26em` → `1.077em` (−~14,5%).

### Note

- Wrappers internos de Gastos usan `height: 100%` como Resumen/Proyectos;
  solo fila + holder usan `calc(100dvh − offset)`.

## [2026-07-27f] — Cierre rama `feat/pestana-unidad-gastos`

### Summary

- Pestaña **Unidad** con tabla AG Grid **Gastos** y vista `bi_v_unidad`.
- Dashboard fit-to-viewport por CSS (`100dvh` − offsets), sin motores JS de altura.
- Totales AG Grid visibles: `ag-theme` anclado al card (`position: absolute; inset: 0`).
- Quita reaplicación conflictiva de alturas al cambiar Resumen ↔ Unidad.

### Fixed

- Pie de totales recortado por `overflow` al forzar alto de tablas.
- Hueco gris / scroll vertical por altura fija del layout JSON en la fila de tabs.
- Flash y pelea de layouts entre Gastos y Resumen/Proyectos.

### Note

- El layout de tablas ya no se recalcula en bucle por JS; solo se publican
  offsets CSS (`--ps-dash-top`, `--ps-tables-top`, `--ps-unidad-top`).

## [2026-07-27e] — Filtro nativo Proyectos

### Added

- Filtro `NATIVE_FILTER-PROYECTO` (multi-select) sobre `proyecto`.
- Scope: Resumen mensual, Proyectos, Evolución, Margen acumulado, Probabilidad.
- Vistas `bi_v_evolucion_mensual` y `bi_v_facturacion_probabilidad` con grano por
  proyecto (sin mostrar la columna en esos charts).

### Note

- KPIs Obj/Plan y Gastos (Unidad) quedan fuera del filtro proyecto.

## [2026-07-27d] — Sin scroll vertical de página (panel filtros)

### Fixed

- El panel de filtros izquierdo ensanchaba el documento (~80px); CSS con
  `overflow-y: auto` solo en `[data-test=dashboard-filters-panel]` (no en el
  hijo sticky: eso ocultaba los controles).

## [2026-07-27c] — Probabilidad: importes en K€

### Fixed

- Etiquetas de Facturación por Probabilidad: importe real en `K€` (p. ej. `5.900 K€`), no la categoría con `€` ni el número completo.

## [2026-07-27b] — Cierre rama `fix/probabilidad-formato-euro-porcentaje`

### Summary

- Formato `%` / `€` en Facturación por Probabilidad + fix CSRF cookies Secure por HTTP.

## [2026-07-27a] — Facturación por Probabilidad: % y €

### Changed

- Etiquetas de probabilidad a la izquierda con sufijo `%` (p. ej. `100%`).
- Importes del eje, barras y tooltip con sufijo `€`.
- Eliminado el título de eje flotante `%` (quedaba suelto en el medio).

### Fixed

- API setup/pull: reenviar cookies `Secure` por HTTP LAN (CSRF session token missing).

## [2026-07-27] — Cierre rama `feat/ag-grid-autosize-columns`

### Added / Changed

- Patrón canónico de tablas AG Grid (Proyectos): autosize, buscador en cabecera, altura completa del card, persistencia de anchos (localStorage + API compartida), sin scroll horizontal fantasma.
- Documentación integral en `docs/TABLAS_AG_GRID.md` y regla `.cursor/rules/superset-table-ag-grid.mdc`.
- Métrica «Fact.» en Resumen/Proyectos; orden cronológico en Resumen mensual; tipografía alineada en Facturación por Probabilidad.

### Fixed

- Snapback de columnas, truncateLongCells, CSRF al recrear chart, permisos de escritura compartida (`dbertona`), altura Proyectos = Resumen.

## [2026-07-26ay] — Resumen: fallback de orden cronológico forzado

### Fixed

- Reintroducida `isHiddenSortColId` (se había perdido y rompía parte del autosize/sort).
- `sortResumenByAnoMes` detecta `colId` real de «Año/Mes» y limpia sort de métricas.
- Fallback duro: si AG Grid ignora sort model, se reasigna `rowData` ordenado por `MM/YYYY`.

## [2026-07-26ax] — Resumen: orden cronológico SQL (to_date)

### Fixed

- Sin `order_by`, Superset ordenaba por Fact. DESC.
- Ahora `ORDER BY to_date(ano_mes, 'MM/YYYY') ASC` + JS limpia sort de métricas.

## [2026-07-26aw] — Resumen: solo ano_mes + sort JS + 4 columnas visibles

### Fixed

- Eliminados `year`/`month` del groupby (ocupaban ancho y cortaban Coste/Margen).
- Orden cronológico de `MM/YYYY` con comparator en `tail_js`.
- Autosize encoge las 4 columnas para que quepan a la izquierda sin scroll.

## [2026-07-26av] — Probabilidad: números = tamaño tablas (fix real)

### Fixed

- Causa: Superset 6 no expone `window.echarts` → el `setOption` no corría.
- Fallback: patch de `canvas.fillText` en Probabilidad con el px medido de las celdas AG Grid (1.26em) y color `#0f172a`.
- Tema `THEME_DEFAULT`: `echartsOptionsOverridesByChartType` para `echarts_timeseries_bar` a 20px.

## [2026-07-26au] — Resumen alineado a la izquierda

### Fixed

- Sin flex en Resumen (el flex empujaba el bloque a la derecha).
- `year`/`month` a ancho 0 + `setColumnVisible(false)` para quitar el hueco izquierdo.

## [2026-07-26at] — Probabilidad: título = otros; números = tablas

### Changed

- Título «Facturación por Probabilidad» vuelve a 16px (igual que el resto).
- Ejes/valores ECharts toman el `font-size` computado de las tablas AG Grid (1.26em).

## [2026-07-26as] — Resumen: métricas a la derecha en pantallas anchas

### Fixed

- Columnas `year`/`month` a ancho 0 (ya no dejan hueco a la izquierda).
- `Año/Mes` absorbe el ancho restante → Fact./Coste/Margen % alineadas a la derecha.
- Sort ASC forzado en year+month vía AG Grid.

## [2026-07-26ar] — Fuente más grande en Facturación por Probabilidad

### Changed

- Título del chart: 20px (antes 16px).
- Ejes y valores ECharts: 15px vía `tail_js` (`setOption`).

## [2026-07-26aq] — Proyectos: sin scroll horizontal fantasma

### Fixed

- Autosize Proyectos: margen viewport + shrink de columna texto al overflow exacto.
- CSS: ocultar barra horizontal AG Grid en Resumen/Proyectos.
- Cabecera Proyectos: métrica `Fact.` (antes `Facturación` truncada).

## [2026-07-26ap] — Resumen mensual: orden cronológico mes/año

### Fixed

- Tabla Resumen: `groupby` year+month+ano_mes y `ORDER BY year, month ASC` (ano_mes `MM/YYYY` no ordenaba bien como texto). Columnas year/month ocultas.

## [2026-07-26b] — Table V2 AG Grid, fuente, búsqueda junto al título, altura completa

### Added
- Table V2 (AG Grid) activado para «Resumen mensual» y «Proyectos» — permite redimensionar columnas con el ratón.
- Campo de búsqueda «Buscar» de Proyectos movido al lado del título mediante input proxy nativo (bypasea re-renders de React).

### Changed
- Fuente de tablas ajustada a 1.33em (base 1.56em −15%).
- Tablas ocupan toda la altura del card: CSS `chart-slice` flexbox + fix JS `fixAgGridHeight` que calcula píxeles disponibles y los aplica inline.
- CSS propaga `height: 100%` por toda la cadena: `.slice_container` → `.chart-container` → `ag-theme-*` → `.ag-root-wrapper` → `.ag-root`.

### Fixed
- Permisos de `dbertona@powersolution.es`: rol Admin añadido (antes solo PS_Viewer).

## [2026-07-26ao] — Tablas: quitar ⋮ que recortaba el ancho

### Fixed

- Resumen/Proyectos: menú ⋮ oculto; padding uniforme; tabla a ancho completo.

## [2026-07-26an] — Menos margen derecho en tablas

### Changed

- Resumen mensual / Proyectos: padding derecho reducido para equilibrar la card.

## [2026-07-26am] — Misma altura Resumen mensual / Proyectos

### Changed

- Layout: altura de Proyectos = Resumen mensual (53 unidades de grid).

## [2026-07-26al] — Separadores verticales en tablas

### Changed

- Tablas Resumen/Proyectos: `border-left/right` explícitos + `border-collapse: separate`.

## [2026-07-26ak] — Columna proyecto → «Proyectos»

### Changed

- Tabla Proyectos: cabecera `Proyectos` (antes `proyecto`).

## [2026-07-26aj] — Columna ano_mes → «Año/Mes»

### Changed

- Tabla Resumen mensual: `customColumnName` / verbose `Año/Mes` (antes `ano_mes`).

## [2026-07-26ai] — Tablas Resumen/Proyectos estilo rejilla Timesheet

### Changed

- CSS tablas: bordes de celda, cabecera gris `#f3f4f6`, padding 10–12px,
  hover suave (look similar a Lista de Notas; sin pastillas de estado).

## [2026-07-26ah] — Títulos teal estilo Timesheet

### Changed

- Títulos de charts/tablas y cabeceras de sección en `#007c89` bold
  (mismo teal que «Lista de Notas» en Timesheet).

## [2026-07-26ag] — Estilo tarjetas tipo Timesheet en Resumen

### Changed

- Fondo dashboard `#eef2f4`, cards blancas con radio 12px y sombra suave.
- KPI con barra lateral de color (Facturación/Margen/Δ/Beneficio).
- Tipografía de etiquetas KPI en mayúsculas; títulos de sección más marcados.

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
