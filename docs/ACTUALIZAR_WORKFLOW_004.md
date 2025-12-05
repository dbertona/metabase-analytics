# Cambios en el Workflow 004

## Resumen

Este documento documenta los cambios realizados en el workflow `004_sync_bc_to_ps_analytics`:
- Sincronización de la tabla `departamentos`
- Agregado del campo `projectteamfilter` a la tabla `configuracion_usuarios`

## ⚠️ Cómo Actualizar el Workflow

**Para actualizar este workflow (o cualquier otro), consulta la guía general:**

👉 **[Guía: Actualizar Workflows Existentes](../shared/n8n/n8n-integration-guide.md#-actualizar-workflows-existentes-método-sqlite-directo)**

### Método Rápido (Script Automatizado)

```bash
# Desde la VM donde está el contenedor n8n
cd /home/metabase
./scripts/update-n8n-workflow-004.sh
```

**Nota:** El script actualiza tanto `workflow_entity` como `shared_workflow` para que la fecha se refleje correctamente en la UI.

## Verificación de Cambios

### Verificar en n8n UI

1. Accede a: `https://n8n-analytics.powersolution.es`
2. Abre el workflow `004_sync_bc_to_ps_analytics`
3. Verifica que existan los siguientes nodos nuevos:
   - ✅ `BC API - Departamentos`
   - ✅ `Transform Departamentos`
   - ✅ `Upsert Departamentos`
   - ✅ `Compute now ISO (Departamentos)`
   - ✅ `Update sync_state (Departamentos)`
   - ✅ `Result Departamentos`
4. Verifica cambios en `ConfiguracionUsuarios`:
   - ✅ Abre `BC API - ConfiguracionUsuarios` y verifica que la URL incluya `projectteamfilter` en el `$select`
   - ✅ Abre `Transform ConfiguracionUsuarios` y verifica que extraiga `projectteamfilter`
   - ✅ Abre `Upsert ConfiguracionUsuarios` y verifica que incluya `projectteamfilter` en el INSERT/UPDATE
   - ✅ Verifica que `Update sync_state (ConfiguracionUsuarios)` esté conectado a `BC API - Tecnologias`

### Verificar desde Terminal

Para verificar cambios específicos de este workflow:

```bash
docker exec n8n python3 << 'PYTHON'
import sqlite3
import json

WORKFLOW_ID = 'l5ux7p339Nejygra'

conn = sqlite3.connect('/home/node/.n8n/database.sqlite')
cursor = conn.cursor()

cursor.execute('SELECT nodes FROM workflow_entity WHERE id = ?', (WORKFLOW_ID,))
nodes = json.loads(cursor.fetchone()[0])

# Verificar nodos de Departamentos
departamentos_nodes = [n for n in nodes if 'Departamentos' in n.get('name', '')]
print(f'Nodos de Departamentos: {len(departamentos_nodes)}')
for node in departamentos_nodes:
    print(f'  - {node.get("name")}')

# Verificar projectteamfilter en ConfiguracionUsuarios
for node in nodes:
    if 'BC API - ConfiguracionUsuarios' in node.get('name', ''):
        url = node.get('parameters', {}).get('url', '')
        print(f'\nprojectteamfilter en BC API: {"projectteamfilter" in url}')

conn.close()
PYTHON
```

**Para métodos de verificación generales, consulta la [guía de n8n](../shared/n8n/n8n-integration-guide.md#verificar-que-se-actualizó-correctamente).**

## Configuración Post-Actualización

Después de actualizar el workflow, debes:

1. **Asignar credenciales a los nuevos nodos:**
   - `BC API - Departamentos`: Asignar credencial OAuth2 de Business Central
   - `Upsert Departamentos`: Asignar credencial de PostgreSQL
   - `Update sync_state (Departamentos)`: Asignar credencial de Supabase

2. **Verificar credenciales existentes:**
   - Los nodos de `ConfiguracionUsuarios` ya deberían tener sus credenciales asignadas

3. **Verificar conexiones:**
   - Asegúrate de que todos los nodos estén conectados correctamente
   - Verifica que `Result Departamentos` se conecte a `Merge Results`
   - Verifica que `Update sync_state (ConfiguracionUsuarios)` esté conectado a `BC API - Tecnologias`

4. **Activar el workflow:**
   - Si está inactivo, actívalo desde la UI de n8n

## Troubleshooting

**Para problemas generales de actualización de workflows, consulta la [guía de troubleshooting](../shared/n8n/n8n-integration-guide.md#errores-comunes-y-soluciones).**

### Problemas Específicos de este Workflow

- **ID del workflow:** `l5ux7p339Nejygra`
- **Archivo local:** `src/workflows/004_sync_bc_to_ps_analytics.json`

## Cambios Realizados en el Workflow

### Tabla Departamentos
- ✅ Añadido "departamentos" a la lista de entidades en `Compute Execution Summary`
- ✅ Añadido "departamentos" a la lista de entidades en `Build sync_state map`
- ✅ Creados 6 nodos nuevos para sincronizar Departamentos
- ✅ Configuradas todas las conexiones entre nodos
- ✅ Conectado `Result Departamentos` a `Merge Results` (índice 2)

### Tabla ConfiguracionUsuarios - Campo projectteamfilter
- ✅ Agregado `projectteamfilter` al `$select` en `BC API - ConfiguracionUsuarios`
- ✅ Agregado `projectteamfilter` a la extracción en `Transform ConfiguracionUsuarios`
- ✅ Agregado `projectteamfilter` al INSERT/UPDATE en `Upsert ConfiguracionUsuarios`
- ✅ Corregida conexión: `Update sync_state (ConfiguracionUsuarios)` → `BC API - Tecnologias`
- ✅ Columna `projectteamfilter VARCHAR(20)` agregada al schema SQL (`scripts/ps_analytics_schema.sql`)

## Referencias

- **[Guía completa de n8n](../shared/n8n/n8n-integration-guide.md)** - Método general para actualizar cualquier workflow
- **Script de actualización:** `scripts/update-n8n-workflow-004.sh`
- **Archivo del workflow:** `src/workflows/004_sync_bc_to_ps_analytics.json`
- **Schema SQL:** `scripts/ps_analytics_schema.sql`





