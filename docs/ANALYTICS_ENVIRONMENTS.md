# Entornos PostgreSQL Analytics

**Última verificación:** 2026-08-14  
**Alcance:** instancias Postgres de Analytics (datos BC / SE). No es la BD Timesheet.

Sync BC → Analytics: [004_SYNC_BC_ANALYTICS.md](./shared/analytics/004_SYNC_BC_ANALYTICS.md)  
Copia entre entornos (script): `power-solution-apps/scripts/copy-analytics-production-to-env.sh`  
Compose: `power-solution-apps/ops/supabase-analytics/docker-compose.{dev,testing,production}.yml`

---

## Matriz

| Entorno | VM | Contenedor | Host:puerto | Password | Directorio |
| --- | --- | --- | --- | --- | --- |
| **DEV** | 102 | `supabase-analytics-db-dev` | `192.168.36.102:5435` | `analytics_dev_2025` | `/opt/supabase-analytics/` |
| **Testing** | 103 | `supabase-analytics-db-testing` | `192.168.36.103:5435` | `analytics_testing_2025` | `/opt/supabase-analytics/` |
| **Producción** | 100 | `supabase-db` | `192.168.36.100:5433` | `SuperSecurePassword2025` | `/opt/supabase/` |

Usuario y database: `postgres` / `postgres` en los tres.

**Puertos publicados (DEV/testing):** Kong `8002`, Studio `3002`. Timesheet usa `8000` / `5433` en la misma VM — no mezclar.

**Prod no es `:5432`.** El puerto verificado desde LAN es **`5433`**.

```bash
# Testing
psql "postgresql://postgres:analytics_testing_2025@192.168.36.103:5435/postgres"

# DEV
psql "postgresql://postgres:analytics_dev_2025@192.168.36.102:5435/postgres"

# Prod
psql "postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres"
```

Desde un host sin `psql` local, el mismo DSN vía `docker exec` en el contenedor de esa VM.

---

## Backend Apps (pool SE, solo lectura)

`app-backend` lee `bi_v_*` / `v_se_*` con `ANALYTICS_DB_*` (`config/analyticsDb.js`).  
**No** usa `ANALYTICS_SUPABASE_*`.

| Entorno | `ANALYTICS_DB_HOST` | Puerto | Password | `.env` en servidor | Estado 2026-08-14 |
| --- | --- | --- | --- | --- | --- |
| **Testing** | `192.168.36.103` | `5435` | `analytics_testing_2025` | `/opt/langchain-agent-v2/.env` | **Apunta a Analytics local** |
| **DEV** | `192.168.36.100` | `5433` | prod | `/opt/langchain-agent-v2/.env` | Sigue leyendo **prod** |
| **Prod** | `192.168.36.100` | `5433` | prod | (VM 101) | Prod |

Tras cambiar el `.env` hay que **recrear** el contenedor (`docker compose up -d --force-recreate --no-deps app-backend`). Un `restart` no recarga env.

Backup del `.env` de testing (antes del corte): `/opt/langchain-agent-v2/.env.bak-analytics-20260814`.

SE en testing: `https://testingapp.powersolution.es/my-timesheet-app/` → Seguimiento Económico.

---

## n8n workflow 004

| Entorno | n8n | Workflow ID | Destino de escritura |
| --- | --- | --- | --- |
| Prod | VM 101 — `https://apps.powersolution.es/n8n/` | `d1f7647e114a486e` | VM 100 `:5433` |
| DEV | VM 102 `:5678` | `d57165bf41a34b8eb215` | `Postgres PS_Analytics` → Analytics DEV (`192.168.36.102:5435`) |
| Testing | VM 103 `:5678` | `dlekAIp9f5FsdfJj` (activo) | credencial `Postgres PS_Analytics` → Analytics testing |

El 004 de testing falló el 2026-08-10 en `Try Acquire Mutex 004`: `company_name` NULL al insertar en `sync_executions`. No se corrigió en este corte.

Canal BC → Analytics: solo 004 (salvo bypass explícito).

**Publicar 004 o vistas/MVs a prod:** `./scripts/deploy-004-gated.sh` (copia prod→testing, valida 021 + cifras publicadas, luego JSON y/o SQL a prod). `--sql-only` / `--004-only` si el cambio es de un solo lado. `apply-bi-views.sh` no escribe fórmulas en prod sin el gate.

**021 / 004 permanentes en testing:** leen `$env.BC_ENVIRONMENT` (Pruebas_PS) y el Analytics de `:5435`. El 021 de testing **no tiene cron** (solo webhook). El gate pinnea Production **solo durante el canary** post-clon y **restaura `$env` al terminar**. Cron L–V solo en n8n **prod** (BC Production vs Analytics prod).

---

## Copia prod → testing (2026-08-14)

Se copió la BD Analytics de **VM 100** a **`supabase-analytics-db-testing`**.

- Backup del testing anterior: `/tmp/testing-analytics-backup-20260814-080803.dump` (VM 103)
- Tablas base: conteos idénticos a prod
- KPI Iberia 2026 (`v_se_facturacion`): P **3.633.350** / R **2.773.861** (igual que prod ese día)

### Tablas que faltaban en testing (creadas desde DDL prod)

- `bc_historico_gastos_mes`
- `bc_historico_mano_obra_mes`
- `bc_historico_unidad_mes`
- `bc_historico_planificacion_mes_backup_20260812`

### PK `bc_expediente_mes`

En testing el PK era más estrecho (`company_name, job_no, year, month, budget_date_year, budget_date_month`).  
En prod incluye también `status, month_closing_status, departamento, description, tipo_proyecto, probability, do_not_consolidate, job_unit_no`.  
Sin alinear el PK, el `COPY` falla por duplicados.

### Limitaciones del script canónico

`copy-analytics-production-to-env.sh` (dump `--data-only`). El gate usa el modo **pipe** (no `--file` / `--direct`).

1. ~~`analytics_align_target_schema_from_source` trata vistas como tablas~~ — corregido: solo `BASE TABLE`. Crea tablas faltantes y alinea PKs tras truncate.
2. `--file` + `pg_restore --disable-triggers` falla en la imagen Supabase (`RI_ConstraintTrigger` system).
3. `--direct` exige `sshpass` en el destino; **103 no lo tiene**.
4. Tras el data copy el script crea `bi_mv_*` / `v_se_*` si faltan y hace `REFRESH`.

Procedimiento que funcionó: truncar destino → `pg_dump --data-only` + `SET session_replication_role = replica` (o restore tabla a tabla) → alinear PK/tablas faltantes → aplicar DDL de vistas desde prod → `REFRESH MATERIALIZED VIEW`.

```bash
# Intento estándar (puede abortar por los puntos de arriba)
cd power-solution-apps
./scripts/copy-analytics-production-to-env.sh --target testing --yes --backup
```

---

## Levantar el stack (si no existe)

```bash
cd power-solution-apps
export SSH_PASS='…'
./scripts/deploy-supabase-analytics.sh testing   # o dev
```

En 103 el stack ya estaba up (db + Kong `8002` + Studio `3002`).

---

## Qué no hacer

- Apuntar el backend de testing otra vez a `192.168.36.100:5433` (rompe el aislamiento).
- Copiar prod → testing sin `--backup`.
- Traer BC → Analytics fuera del 004.
- Tocar prod sin aprobación explícita en el chat.
