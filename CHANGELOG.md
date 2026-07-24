# Changelog — superset-analytics

## [Unreleased]

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

### Investigación Coste R Analytics vs PBI (jul 2026)

**Síntoma:** Analytics muestra 2.513.515 €, PBI muestra 2.381.218 € → gap de ~132.297 €.

**Causa raíz confirmada:** PBI filtra implícitamente los registros de `movimientosProyectosMes`
que **no tienen `departamento` asignado**. Analytics incluye todos los registros sin distinción.

**Proyectos afectados:**

| Proyecto | Descripción | tipo_proyecto | type_line | Coste 2026 |
|----------|-------------|--------------|-----------|------------|
| `PSI-AR-26-1200` | PS Argentina 2026 | Structure | G/L Account | 131.700 € |
| `PSI-CO-26-7000` | (Structure) | Structure | G/L Account | 14,99 € (mes 3) |
| **Total** | | | | **~131.715 €** |

Residual no explicado (~582 €) es irrelevante (lag de réplica BC).

**Desglose mes a mes de PSI-AR-26-1200:**

| Mes | Coste BC/Analytics | PBI excluye |
|-----|--------------------|-------------|
| 1 | 20.000 € | ✅ (sin dpto) |
| 2 | 20.000 € | ✅ (sin dpto) |
| 3 | 20.000 € | ✅ (sin dpto) |
| 4 | 20.000 € | ✅ (sin dpto) |
| 5 | 20.000 € | ✅ (sin dpto) |
| 6 | 31.700 € (2 reg.) | ✅ (sin dpto) |

**Acción requerida (en BC):** Asignar un código de departamento a los proyectos `PSI-AR-26-1200`
y `PSI-CO-26-7000` en la ficha de proyecto de Business Central. Tras el cambio y el siguiente
refresco de PBI, el coste pasará a ~2.513k (paridad con Analytics y BC Production).

Mientras tanto: la diferencia de 132k es **por diseño** — PBI excluye costes sin departamento,
Analytics los incluye. Ambas cifras son correctas según su scope.

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
