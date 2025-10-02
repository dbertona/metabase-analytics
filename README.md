# Metabase Docker Setup

Configuración completa de Metabase con Docker para análisis de datos y visualizaciones.

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





