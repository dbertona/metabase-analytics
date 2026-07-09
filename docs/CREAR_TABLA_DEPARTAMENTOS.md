# Crear Tabla Departamentos en Supabase

## Resumen

Se ha creado la tabla `departamentos` para sincronizar datos desde Business Central usando el workflow de n8n.

**Query BC:** PS_Departamentos (ID 7000104)
**EntityName:** 'Departamentos'
**EntitySetName:** 'Departamentos'
**Dimension Code:** 'DPTO' (filtrado automáticamente)

## Estructura de la Tabla

```sql
CREATE TABLE IF NOT EXISTS public.departamentos (
    company_name TEXT NOT NULL,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100),
    dimension_code VARCHAR(20) DEFAULT 'DPTO',
    last_modified_datetime TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (company_name, code)
);
```

## Pasos para Crear la Tabla

### Opción 1: Desde Supabase Studio (Recomendado)

1. Accede a Supabase Studio desde tu Mac:
   ```
   http://192.168.36.100:3001/
   ```

2. Ve a **SQL Editor**

3. Copia y pega el contenido de `scripts/create_departamentos_table.sql`

4. Ejecuta el script

### Opción 2: Desde la Línea de Comandos (en la VM)

```bash
# Conectarse a la base de datos de Supabase
docker exec -i supabase-db psql -U postgres -d postgres < scripts/create_departamentos_table.sql
```

### Opción 3: Desde tu Mac con psql

```bash
# Si tienes psql instalado en tu Mac
psql -h 192.168.36.100 -p 5433 -U postgres -d postgres -f scripts/create_departamentos_table.sql
```

## Verificar que la Tabla se Creó

```sql
-- Verificar estructura
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'departamentos'
ORDER BY ordinal_position;

-- Verificar índices
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'departamentos';

-- Verificar triggers
SELECT
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'departamentos';
```

## Actualizar sync_state

Después de crear la tabla, debes añadir el registro en `sync_state` para que el workflow pueda sincronizarlo:

```sql
-- Para Power Solution Iberia SL
INSERT INTO public.sync_state (company_name, entity, last_sync_at)
VALUES ('Power Solution Iberia SL', 'departamentos', '1970-01-01 00:00:00+00'::timestamp with time zone)
ON CONFLICT (company_name, entity) DO NOTHING;

-- Para PS LAB CONSULTING SL
INSERT INTO public.sync_state (company_name, entity, last_sync_at)
VALUES ('PS LAB CONSULTING SL', 'departamentos', '1970-01-01 00:00:00+00'::timestamp with time zone)
ON CONFLICT (company_name, entity) DO NOTHING;
```

O ejecuta el script completo:
```bash
docker exec -i supabase-db psql -U postgres -d postgres < scripts/init_sync_state.sql
```

## Mapeo de Campos desde BC

| Campo BC (API) | Campo Supabase | Tipo | Notas |
|----------------|----------------|------|-------|
| `code` | `code` | VARCHAR(20) | Código del departamento |
| `name` | `name` | VARCHAR(100) | Nombre del departamento |
| `dimensionCode` | `dimension_code` | VARCHAR(20) | Siempre 'DPTO' |
| - | `company_name` | TEXT | Añadido por el workflow |
| - | `last_modified_datetime` | TIMESTAMP | Añadido por el workflow |
| - | `updated_at` | TIMESTAMP | Auto-actualizado por trigger |
| - | `created_at` | TIMESTAMP | Auto-generado |

## Configuración del Workflow n8n

El workflow debe:

1. **Endpoint BC:** `/v2.0/companies({companyId})/Departamentos`
2. **Mapeo de campos:**
   - `code` → `code`
   - `name` → `name`
   - `dimensionCode` → `dimension_code` (debe ser 'DPTO')
3. **Primary Key:** `(company_name, code)`
4. **ON CONFLICT:** `(company_name, code) DO UPDATE SET ...`

## Índices Creados

- `idx_departamentos_company` - Para búsquedas por compañía
- `idx_departamentos_code` - Para búsquedas por código
- `idx_departamentos_dimension_code` - Para filtros por dimensión

## Triggers

- `update_departamentos_updated_at` - Actualiza automáticamente `updated_at` en cada UPDATE

## Próximos Pasos

1. ✅ Crear la tabla (script listo)
2. ⏳ Ejecutar el script en Supabase
3. ⏳ Actualizar `sync_state`
4. ⏳ Configurar el workflow en n8n
5. ⏳ Probar la sincronización






