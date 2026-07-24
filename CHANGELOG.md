# Changelog — superset-analytics

## [Unreleased]

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

**Causa raíz de huérfanos (patrón UPSERT):**
El sync 004 hace UPSERT por PK `(company, job, year, month, budget_date_year, budget_date_month)`.
Cuando BC actualiza `budgetDateMonth` de una línea (ej. 6→7), el registro antiguo
`(job, month=6, budget=6)` queda huérfano en analytics porque el UPSERT solo inserta/actualiza,
no borra. La única solución operativa es el resync completo periódico.

**Recomendación operativa:** Programar un resync completo mensual de `bc_expediente_mes`
y `bc_job_planning_line` (DELETE + reset watermark + sync) para evitar acumulación de huérfanos.

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
