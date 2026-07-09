# 📊 Superset Analytics - Power Solution

Configuración de Superset (y legado Metabase) con Docker para análisis de datos y visualizaciones del ecosistema Power Solution.

**Integrado con:** Supabase (Timesheet + Expenses) + Business Central (OData)

## 🚨 CRÍTICO: Gitea es el Repositorio Principal

**⚠️ REGLA OBLIGATORIA: SIEMPRE hacer push a Gitea, NUNCA a GitHub directamente.**

- ✅ **SIEMPRE** `git push gitea main` (Gitea es el repositorio principal)
- ❌ **NUNCA** `git push origin main` (GitHub es solo mirror de respaldo)

**Documentación completa:**
- `docs/shared/GITEA_VS_GITHUB.md` 🚨 **CONFIGURACIÓN DE REMOTES**
- `docs/shared/DOCUMENTATION_INDEX.md` - Índice completo de documentación

**Repositorio Gitea:** `http://192.168.36.104:3000/admin/superset-analytics`

**Mirror GitHub (solo lectura/respaldo):** `https://github.com/dbertona/metabase-analytics`

## Estructura del Proyecto

```
metabase-docker/
├── docker-compose.yml    # Configuración de servicios
├── .env                  # Variables de entorno
├── README.md            # Este archivo
├── scripts/             # Scripts de gestión
│   ├── start.sh         # Iniciar servicios
│   ├── stop.sh          # Parar servicios
│   └── backup.sh        # Backup de datos
└── data/                # Datos persistentes
    ├── metabase/        # Datos de Metabase
    └── postgres/        # Datos de PostgreSQL
```

## Inicio Rápido

1. **Configurar variables de entorno**:
   ```bash
   cp .env.example .env
   # Editar .env con tus configuraciones
   ```

2. **Iniciar servicios**:
   ```bash
   ./scripts/start.sh
   ```

3. **Acceder a Metabase**:
   - URL: http://localhost:3000
   - Usuario: admin@metabase.local
   - Contraseña: (se configura en el primer acceso)

## Gestión de Servicios

- **Iniciar**: `./scripts/start.sh`
- **Parar**: `./scripts/stop.sh`
- **Backup**: `./scripts/backup.sh`
- **Logs**: `docker-compose logs -f`

## Configuración

### Variables de Entorno Importantes

- `MB_DB_TYPE`: Tipo de base de datos (postgres)
- `MB_DB_HOST`: Host de la base de datos
- `MB_JETTY_PORT`: Puerto de Metabase (3000)
- `MB_ENCRYPTION_SECRET_KEY`: Clave de encriptación (cambiar en producción)

### Puertos

- **3000**: Metabase Web Interface
- **5432**: PostgreSQL Database

## Backup y Restauración

Los datos se almacenan en volúmenes Docker persistentes:
- Metabase: `./data/metabase/`
- PostgreSQL: `./data/postgres/`

## Seguridad

⚠️ **IMPORTANTE**: Cambiar todas las contraseñas por defecto antes de usar en producción.

## 🔌 Integración con Power Solution

### n8n Workflows

**⚠️ IMPORTANTE**: Si usas workflows de n8n que interactúan con Supabase, configura n8n primero:

- **Setup inicial**: `docs/SETUP_N8N_INICIAL.md` 🔴 **LEER PRIMERO**
- **Troubleshooting DNS**: `docs/TROUBLESHOOTING_N8N_KONG_DNS.md`
- **Guía de integración**: `docs/shared/n8n/n8n-integration-guide.md`

### Conexión a Supabase

Metabase puede conectarse directamente a la base de datos de Supabase para analizar:
- ⏰ Datos de Timesheet
- 💰 Datos de Expenses
- 👥 Usuarios y permisos
- 📊 Métricas de uso

**Configuración automática:**
```bash
./scripts/configure-supabase.sh
```

**Configuración manual:**
1. En Metabase: Admin → Databases → Add Database
2. Tipo: PostgreSQL
3. Host: `db.qfpswxjunoepznrpsltt.supabase.co`
4. Puerto: `5432`
5. Database: `postgres`
6. User/Password: (de Supabase)

**Credenciales y configuración:**
- `docs/SUPABASE_ANON_KEY.md` - API keys de Supabase
- `docs/CREDENCIALES_POSTGRES_SUPABASE.md` - Credenciales PostgreSQL

### Conexión a Business Central (OData)

Ver `scripts/create-api-endpoint.sh` para configurar acceso a APIs de Business Central.

---

## 📊 Dashboards

### Seguimiento Económico PS (réplica Power BI)

**Guía maestra:** [`docs/GUIA_COMPLETA_ANALYTICS.md`](docs/GUIA_COMPLETA_ANALYTICS.md) — arquitectura, BD, sync 004, KPIs, operaciones.

| Documento | Contenido |
|-----------|-----------|
| [GUIA_COMPLETA_ANALYTICS.md](docs/GUIA_COMPLETA_ANALYTICS.md) | Todo lo que tenemos y cómo funciona |
| [seguimiento-economico/README.md](docs/seguimiento-economico/README.md) | Fases PBI, páginas del informe |
| [ACTUALIZAR_WORKFLOW_004.md](docs/ACTUALIZAR_WORKFLOW_004.md) | Deploy n8n y sync |

Views SQL canónicas: `power-solution-apps/supabase/migrations/20260702180000_*`

### Planificación PS Analytics ⭐

Réplica del dashboard Power BI con KPIs de Objetivos Anuales y Planificación Actual.

**Componentes:**
- 8 tarjetas KPI (Facturación, Margen, Crecimiento, Beneficio × 2 secciones)
- Tabla resumen por sección
- Gráficos de evolución mensual (facturación y margen)
- Filtros: Año, Empresa, Departamento, Tipo P/R

**Setup Metabase (una sola vez):**

```bash
# 1. Aplicar vistas SQL en PS Analytics
docker exec -i supabase-db psql -U postgres -d postgres \
  < scripts/sql/mb_dashboard_planificacion_views.sql

# 2. Conectar Metabase a supabase-db (si no está en la misma red Docker)
docker network connect ps_admin_default metabase

# 3. Crear dashboard en Metabase
export MB_EMAIL="tu-email@powersolution.es"
export MB_PASSWORD="tu-contraseña"
python3 scripts/setup-dashboard-planificacion.py
```

**Setup Superset POC:**

```bash
./scripts/start-superset.sh
export SUPERSET_URL=http://localhost:8088 SUPERSET_USER=admin SUPERSET_PASSWORD='...'
python3 scripts/setup-superset-planificacion.py
```

**Vistas SQL:** `scripts/sql/mb_dashboard_planificacion_views.sql` (Metabase) · `scripts/sql/bi_dashboard_planificacion_views.sql` (Superset/BI)

**Documentación de datos:**
- Objetivos → `bc_objectives_by_department`
- Planificación (P) → `bc_historico_planificacion_mes` (último cierre del año)
- Real (R) → `bc_job_ledger_entry_month`
- Crecimiento → vs facturación real del año anterior

### Pendientes

- [ ] Dashboard de Horas por Proyecto
- [ ] Dashboard de Gastos por Departamento

---

## Troubleshooting

### Verificar estado de servicios
```bash
docker-compose ps
```

### Ver logs de errores
```bash
docker-compose logs metabase
docker-compose logs postgres
```

### Reiniciar servicios
```bash
docker-compose restart
```

### Verificar conexión a Supabase
```bash
./scripts/test-supabase-connection.sh
```

### Problemas con n8n y Supabase

Si n8n no puede conectarse a Supabase (error "getaddrinfo EAI_AGAIN kong"):

```bash
# Verificar y conectar n8n a la red de Supabase
./scripts/ensure-n8n-network.sh

# Ver documentación completa
cat docs/TROUBLESHOOTING_N8N_KONG_DNS.md
```

**Documentación relacionada:**
- `docs/SETUP_N8N_INICIAL.md` - Configuración inicial de n8n
- `docs/TROUBLESHOOTING_N8N_KONG_DNS.md` - Solución al error DNS "kong"
- `docs/shared/n8n/n8n-integration-guide.md` - Guía completa de n8n





