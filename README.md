# 📊 Metabase Analytics - Power Solution

Configuración completa de Metabase con Docker para análisis de datos y visualizaciones del ecosistema Power Solution.

**Integrado con:** Supabase (Timesheet + Expenses) + Business Central (OData)

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

### Conexión a Business Central (OData)

Ver `scripts/create-api-endpoint.sh` para configurar acceso a APIs de Business Central.

---

## 📊 Dashboards Preconfigurados

_(Próximamente)_

- [ ] Dashboard de Horas por Proyecto
- [ ] Dashboard de Gastos por Departamento
- [ ] Dashboard de Aprobaciones Pendientes
- [ ] Dashboard de Productividad

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





