# Workflow 004 — Sync BC → Analytics

> **Guía completa:** [004_SYNC_BC_ANALYTICS.md](../shared/analytics/004_SYNC_BC_ANALYTICS.md)

## Arquitectura (2026-07)

| Componente | Ubicación |
|------------|-----------|
| **Workflow 004 (canónico en este repo)** | `src/workflows/004_sync_bc_to_ps_analytics.json` |
| **n8n producción** | `https://apps.powersolution.es/n8n/` (VM **101**, `n8n-prod`) |
| **ID workflow prod** | `d1f7647e114a486e` |
| **n8n DEV** | VM 102 — workflow ID `d57165bf41a34b8eb215` |
| **PostgreSQL Analytics prod** | VM **100** — `192.168.36.100:5433` (`supabase-db`) |
| **PostgreSQL Analytics testing** | VM **103** — `192.168.36.103:5435` (`supabase-analytics-db-testing`) |
| **n8n testing (004)** | VM 103 — ID `dlekAIp9f5FsdfJj` |

Entornos y backend: [ANALYTICS_ENVIRONMENTS.md](./ANALYTICS_ENVIRONMENTS.md).

> **Retirado:** n8n en VM 100 (puerto 5678). No usar.

---

## Ejecutar sync

```bash
curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi'

curl -sS -m 900 -X POST \
  'https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=pslab'
```

**BC:** `BC_ENVIRONMENT=Production` en n8n-prod.

---

## Publicar 004 o vistas que mueven cifras

**Canal obligatorio:** `./scripts/deploy-004-gated.sh`.

Cubre el JSON 004 **y** SQL que alimenta Apps/PBI (`v_se_*`, `bi_v_*`, `bi_mv_*`).  
No aplicar JSON a n8n prod ni `CREATE OR REPLACE` en Analytics prod sin pasar el gate.

El gate:

1. Seatbelt estático 004 (Transform PlanificacionMes = SUM, sin `pbiKey` / Distinct), si el alcance incluye 004.
2. Copia Analytics **prod → testing** (escribe solo en VM 103).
3. Si hay SQL: snapshot de `v_se_facturacion` (empresa + depto `1-02`) → aplica `v_se_*` + `bi_*` **solo en testing** → compara vs snapshot (tol 0,50 €). Un cambio que deba mover cifras exige `--allow-figure-change`.
4. Si hay 004: JSON del repo a n8n **testing** (004 + 021). En testing el contenedor tiene `BC_ENVIRONMENT=Pruebas_PS`; el gate **pinnea Production solo en esos workflows**. El 021 de testing **no lleva cron** (solo webhook): comparar BC prod vs clon testing solo vale justo después del clon.
5. Reset de watermarks + canary 004 (`planificacion_mes`, `movimientos_proyectos`, `expediente_mes`, `meses_cerrados`) en psi y pslab (solo alcance 004).
6. 021 en testing **bajo demanda** (gate / webhook): `tipo_p_planif_sum`, `tipo_r_sum`, `tipo_p_expediente_sum` (tol 0,50 €). El cron L–V del 021 vive solo en n8n **prod**.
7. Cifras publicadas: `bi_mv_planificacion_kpi` == `v_se_facturacion`; `v_se` tipo R == 021 `tipo_r_sum` BC. Si falla → **no se toca prod**.
8. Si cierran: mismo JSON a n8n prod y/o mismo SQL a Analytics prod. **No lanza 004 en prod.**

```bash
cd superset-analytics
./scripts/deploy-004-gated.sh --yes                 # 004 + SQL
./scripts/deploy-004-gated.sh --yes --sql-only      # solo vistas/MVs
./scripts/deploy-004-gated.sh --yes --004-only      # solo JSON 004
./scripts/deploy-004-gated.sh --yes --no-prod       # solo veredicto testing
./scripts/deploy-004-gated.sh --yes --skip-copy     # clon testing ya fresco
```

`apply-bi-views.sh` (sin `--refresh`) está bloqueado contra prod.  
⛔ No exportar 004 de prod y parchear un nodo (reintroduce Distinct).  
⛔ No lanzar 004 desde n8n DEV hasta aislar `Postgres PS_Analytics`.  
`update-n8n-workflow-004-api.sh` ya no hace PUT a prod: redirige aquí.

### Emergencia (solo con OK explícito, sin gate)

```bash
# 1) Copiar script y JSON al servidor 101
sshpass -p 'PsAdmin2025' scp \
  /ruta/power-solution-apps/scripts/update_n8n_workflow_postgres.py \
  src/workflows/004_sync_bc_to_ps_analytics.json \
  ps_admin@192.168.36.101:/tmp/

# 2) Ejecutar en el servidor
sshpass -p 'PsAdmin2025' ssh ps_admin@192.168.36.101 bash << 'REMOTE'
export N8N_DB_PASSWORD="c7DxE3KNX72LlRzYPf5KGDskeM84jWvn"
python3 /tmp/update_n8n_workflow_postgres.py update \
  d1f7647e114a486e \
  /tmp/004_sync_bc_to_ps_analytics.json
REMOTE
```

---

## Post-sync: materializadas BI (`bi_mv_*`)

Tras un sync OK, el nodo `Refresh BI Materialized Views` refresca **todas**
las matviews de `public` (`pg_matviews`), no una lista fija. Así no se
quedan atrás p. ej. `bi_mv_mano_obra_recursos_*` (Recursos/Perfiles).
Los datasets Apps/`bi_v_*` son wrappers. Publicar SQL a prod:

```bash
./scripts/deploy-004-gated.sh --yes --sql-only
```

`--refresh` (no cambia fórmulas) sigue permitido a mano:

```bash
ANALYTICS_DSN='postgresql://postgres:analytics_testing_2025@192.168.36.103:5435/postgres' \
  ./scripts/apply-bi-views.sh --refresh
```

## Verificar sync

```bash
sshpass -p 'PsAdmin2025' ssh ps_admin@192.168.36.100 \
  "docker exec supabase-db psql -U postgres -d postgres -c \"
SELECT * FROM v_se_kpi_cards WHERE empresa = 'Power Solution Iberia SL' AND ano = 2026;
\""
```

Esperado plan PSI 2026: **4.193.215 €** (`v_se_kpi_cards`, incluye tipo P + objetivos).

> Desglose solo tipo P en `v_se_facturacion`: **3.712.450 €** — ver `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md` §6.2.

---

## Troubleshooting: `historico_planificacion_mes` → Invalid string length

Síntoma: sync Iberia `partial_error`, solo falla histórico; watermark
`bc_historico_planificacion_mes` no avanza (o avanza sin escribir filas).

Causa: un único GET OData / Discovery del delta acumula demasiado JSON en n8n
(límite V8). Empeora con modificaciones masivas en BC (p. ej. 42k filas el
2026-08-03).

Fix (2026-08-04b): **sin Discovery**. Particiones year|month estáticas +
`lastModifiedDateTime ge watermark` por Snapshot + `SplitInBatches` +
`Loop Feedback`. Ver CHANGELOG `[2026-08-04b]`.

Comprobar watermark y datos recientes:

```sql
SELECT entity, last_sync_at
FROM sync_state
WHERE company_name = 'Power Solution Iberia SL'
  AND entity = 'bc_historico_planificacion_mes';

SELECT MAX(updated_at), COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 day')
FROM bc_historico_planificacion_mes
WHERE company_name ILIKE '%Iberia%';
```

Si el watermark avanzó sin datos (falso positivo): resetear a la última
`MAX(updated_at)` real y re-lanzar sync solo de `historico_planificacion_mes`.

---

## Incidente 2026-08-12: Plan histórico de Unidad "demasiado bajo"

### Síntoma observado

- En `Unidad` (depto `1-02`, marzo 2026), el `Planificado` quedaba muy por debajo de BC.
- Referencia BC `Pruebas_PS`:
  - `Power Solution Iberia` (`closingMonthCode=2026.02`): **39,440.46**
  - `Power Lab Iberia` (`closingMonthCode=2026.02`): **9,468.22**

### Causa raíz (confirmada)

1. En `Transform HistoricoPlanificacionMes` se usaban claves casi fijas para PK:
   - `nr=''`, `type_line='P'`, `line_type=''`
2. El upsert en `bc_historico_planificacion_mes` usa PK:
   - `(company_name, job_no, year, month, closing_month_code, nr, type_line, line_type)`
3. Resultado: filas distintas de BC colisionaban y se sobrescribían en Analytics.
4. Además coexistían filas históricas antiguas (clave `P`) con nuevas, mezclando resultados.

### Corrección aplicada en producción

1. **Workflow 004 (prod) actualizado** en nodo `Transform HistoricoPlanificacionMes`:
   - Agregación por grano real de API:
     `job,year,month,closingMonthCode,departamento,descripcion,estado,tipoProyecto,probability,status1`
   - Suma de `invoice/cost/quantity`.
   - Generación de `nr` estable (hash), `type_line='HPM'`, `line_type='HIST'`.
2. **Limpieza controlada 2026** en `bc_historico_planificacion_mes` (PSI + PSLAB).
3. Reset de watermark (`sync_state`) y relanzado de 004 solo para:
   - `historico_planificacion_mes`
   - `sinceYear=2026`, `untilYear=2026`
4. Rebuild de `bc_historico_unidad_mes` con lógica M-1 y `REFRESH` de `bi_mv_unidad`.

### Comandos de verificación (post-fix)

```sql
-- Fuente histórica (estructura) por cierre, marzo 2026, depto 1-02
SELECT company_name, closing_month_code, ROUND(SUM(cost)::numeric,2) AS cost
FROM bc_historico_planificacion_mes
WHERE year=2026 AND month=3
  AND departamento='1-02'
  AND tipo_proyecto='Structure'
GROUP BY company_name, closing_month_code
ORDER BY company_name, closing_month_code;

-- Validación final en vista de Unidad (tipo P)
SELECT empresa, tipo, ROUND(SUM(COALESCE(m03,0))::numeric,2) AS mar_2026
FROM bi_v_unidad
WHERE year=2026
  AND department_code='1-02'
  AND empresa IN ('Power Solution Iberia SL','PS LAB CONSULTING SL')
GROUP BY empresa,tipo
ORDER BY empresa,tipo;
```

### Resultado final validado

- `Unidad` marzo 2026 (`tipo='P'`, depto `1-02`):
  - `Power Solution Iberia SL`: **39,440.46**
  - `PS LAB CONSULTING SL`: **9,468.22**
- Coincide con BC `Pruebas_PS` para `closingMonthCode=2026.02` (cierre M-1).

### Lección operativa

- Nunca usar claves "placeholder" en transform si forman parte de la PK de destino.
- Para histórico de BC con riesgo de colisión, primero definir grano de negocio y luego la PK técnica.
- Si hubo cambios de grano/PK, limpiar rango afectado antes de re-sync para evitar mezcla de versiones.

### Runbook corto de emergencia (10 pasos)

> Objetivo: recuperar rápidamente `historico_planificacion_mes` y `Unidad` cuando el plan histórico quede deflactado.
> Entorno: producción (`n8n-prod` VM 101 + analytics VM 100).

1. **Verificar síntoma en Analytics (depto/mes afectado)**
   ```sql
   SELECT empresa, tipo, ROUND(SUM(COALESCE(m03,0))::numeric,2) AS mar_2026
   FROM bi_v_unidad
   WHERE year=2026 AND department_code='1-02'
   GROUP BY empresa,tipo
   ORDER BY empresa,tipo;
   ```

2. **Verificar referencia en BC (`Pruebas_PS`)**
   - Comparar `historicoPlanificacionMes` por `closingMonthCode` (M-1 esperado para Plan de mes cerrado).

3. **Confirmar que 004 en prod tiene el transform correcto**
   - Nodo: `Transform HistoricoPlanificacionMes`
   - Debe agregar por grano real y no usar `nr/type_line/line_type` fijos.

4. **(Si aplica) desplegar workflow 004 en prod**
   ```bash
   export DEPLOY_HOST_IP='192.168.36.101' DEPLOY_SSH_USER='ps_admin' DEPLOY_SSH_PASSWORD='PsAdmin2025'
   export N8N_APP_CONTAINER='n8n-prod' N8N_PG_CONTAINER='supabase-db'
   /Users/marcelodanielbertona/POWER-SOLUTION-PROJECTS/power-solution-apps/scripts/update-n8n-workflow-postgres-remote.sh \
     d1f7647e114a486e \
     /Users/marcelodanielbertona/POWER-SOLUTION-PROJECTS/superset-analytics/superset-analytics/src/workflows/004_sync_bc_to_ps_analytics.json
   ```

5. **Purgar el año afectado en `bc_historico_planificacion_mes`**
   ```sql
   DELETE FROM public.bc_historico_planificacion_mes
   WHERE company_name IN ('Power Solution Iberia SL','PS LAB CONSULTING SL')
     AND year=2026;
   ```

6. **Resetear watermark de histórico**
   ```sql
   UPDATE public.sync_state
   SET last_sync_at='1900-01-01T00:00:00Z'
   WHERE entity='bc_historico_planificacion_mes'
     AND company_name IN ('Power Solution Iberia SL','PS LAB CONSULTING SL');
   ```

7. **Lanzar 004 solo para histórico, año objetivo**
   ```bash
   curl -sS -X POST "http://192.168.36.101:5678/webhook/sync-bc-to-analytics?company=psi" \
     -H "Content-Type: application/json" \
     -d '{"entities":["historico_planificacion_mes"],"sinceYear":2026,"untilYear":2026,"reason":"runbook-fix-psi"}'

   curl -sS -X POST "http://192.168.36.101:5678/webhook/sync-bc-to-analytics?company=pslab" \
     -H "Content-Type: application/json" \
     -d '{"entities":["historico_planificacion_mes"],"sinceYear":2026,"untilYear":2026,"reason":"runbook-fix-pslab"}'
   ```

8. **Rehidratar `bc_historico_unidad_mes` (lógica cierre M-1)**
   ```sql
   TRUNCATE TABLE public.bc_historico_unidad_mes;

   INSERT INTO public.bc_historico_unidad_mes (
     company_name, job_no, year, month, concepto_analitico_descripcion, cost, updated_at
   )
   SELECT
     h.company_name,
     h.job_no::text,
     h.year,
     h.month,
     COALESCE(NULLIF(TRIM(h.description::text), ''), h.job_no::text),
     SUM(COALESCE(h.cost, 0))::numeric(18,5),
     now()
   FROM public.bc_historico_planificacion_mes h
   WHERE h.tipo_proyecto ILIKE 'Structure'
     AND NULLIF(BTRIM(h.closing_month_code::text), '') IS NOT NULL
     AND h.closing_month_code = to_char((make_date(h.year,h.month,1) - interval '1 month'),'YYYY.MM')
     AND ABS(COALESCE(h.cost,0)) > 0.0001
   GROUP BY h.company_name,h.job_no,h.year,h.month,COALESCE(NULLIF(TRIM(h.description::text), ''), h.job_no::text);
   ```

9. **Refrescar materializada de Unidad**
   ```sql
   REFRESH MATERIALIZED VIEW public.bi_mv_unidad;
   ```

10. **Validación final obligatoria**
    - `bi_v_unidad` (`tipo='P'`) debe cuadrar con BC `Pruebas_PS` en `closingMonthCode = M-1`.
    - Si no cuadra:
      - revisar mezcla de filas antiguas en `bc_historico_planificacion_mes` (`type_line='P'` legacy),
      - repetir pasos 5→10.

---

## Referencias

- `src/workflows/004_sync_bc_to_ps_analytics.json` — definición del workflow en este repo
- `docs/shared/analytics/004_SYNC_BC_ANALYTICS.md` — arquitectura y operación Analytics (DB + sync 004)
- `docs/shared/n8n/N8N_GUIDE.md`
