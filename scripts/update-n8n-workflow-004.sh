#!/bin/bash
# Script para actualizar el workflow 004_sync_bc_to_ps_analytics en n8n
# Usa el método SQLite directo para evitar crear duplicados
#
# Uso: ./scripts/update-n8n-workflow-004.sh
#
# Requisitos:
# - El archivo src/workflows/004_sync_bc_to_ps_analytics.json debe existir
# - Contenedor n8n corriendo en esta VM

set -e

WORKFLOW_FILE="src/workflows/004_sync_bc_to_ps_analytics.json"
WORKFLOW_NAME="004_sync_bc_to_ps_analytics"
N8N_CONTAINER="n8n"

echo "🔧 Actualizando workflow 004 en n8n..."
echo ""

# Verificar que el archivo existe
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "❌ Error: No se encuentra el archivo $WORKFLOW_FILE"
    exit 1
fi

# Validar JSON
if ! python3 -m json.tool "$WORKFLOW_FILE" > /dev/null 2>&1; then
    echo "❌ Error: El archivo JSON no es válido"
    exit 1
fi

echo "✅ Archivo JSON válido"
echo ""

# Obtener el ID del workflow (primero del JSON, luego desde n8n si no está)
WORKFLOW_ID=$(python3 << 'PYTHON'
import json
import sys
try:
    with open('src/workflows/004_sync_bc_to_ps_analytics.json', 'r') as f:
        data = json.load(f)
        print(data.get('id', ''))
except:
    print('')
PYTHON
)

# Si no está en el JSON, obtenerlo desde n8n
if [ -z "$WORKFLOW_ID" ]; then
    echo "📋 Obteniendo ID del workflow desde n8n..."
    WORKFLOW_ID=$(docker exec $N8N_CONTAINER python3 << 'PYTHON'
import sqlite3
conn = sqlite3.connect('/home/node/.n8n/database.sqlite')
cursor = conn.cursor()
cursor.execute('SELECT id FROM workflow_entity WHERE name = ?', ('004_sync_bc_to_ps_analytics',))
row = cursor.fetchone()
if row:
    print(row[0])
else:
    print('NOT_FOUND')
conn.close()
PYTHON
)
fi

if [ -z "$WORKFLOW_ID" ] || [ "$WORKFLOW_ID" = "NOT_FOUND" ]; then
    echo "❌ Error: No se encontró el workflow '$WORKFLOW_NAME' en n8n"
    echo "   El workflow debe existir antes de actualizarlo"
    exit 1
fi

echo "✅ Workflow ID: $WORKFLOW_ID"
echo ""

# Copiar el archivo al contenedor
echo "📤 Copiando archivo al contenedor n8n..."
docker cp "$WORKFLOW_FILE" "$N8N_CONTAINER:/tmp/workflow_updated.json"

if [ $? -ne 0 ]; then
    echo "❌ Error: No se pudo copiar el archivo al contenedor"
    exit 1
fi

echo "✅ Archivo copiado"
echo ""

# Actualizar el workflow en SQLite
echo "🔄 Actualizando workflow en n8n (método SQLite directo)..."
docker exec $N8N_CONTAINER sh -c "python3 << 'ENDPYTHON'
import json
import sqlite3
from datetime import datetime, timezone
import sys

WORKFLOW_ID = '$WORKFLOW_ID'

sys.stdout.write('Leyendo archivo...\n')
sys.stdout.flush()
with open('/tmp/workflow_updated.json', 'r') as f:
    workflow = json.load(f)

sys.stdout.write('Conectando a BD...\n')
sys.stdout.flush()
conn = sqlite3.connect('/home/node/.n8n/database.sqlite')
cursor = conn.cursor()

# Verificar que el workflow existe
cursor.execute('SELECT id, name FROM workflow_entity WHERE id = ?', (WORKFLOW_ID,))
row = cursor.fetchone()

if not row:
    sys.stdout.write(f'❌ Error: Workflow con ID {WORKFLOW_ID} no existe\n')
    sys.stdout.flush()
    sys.exit(1)

sys.stdout.write('Actualizando...\n')
sys.stdout.flush()
now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

cursor.execute('''
    UPDATE workflow_entity
    SET nodes = ?,
        connections = ?,
        settings = ?,
        staticData = ?,
        pinData = ?,
        versionId = ?,
        updatedAt = ?
    WHERE id = ?
''', (
    json.dumps(workflow.get('nodes', [])),
    json.dumps(workflow.get('connections', {})),
    json.dumps(workflow.get('settings', {})),
    json.dumps(workflow.get('staticData')) if workflow.get('staticData') else None,
    json.dumps(workflow.get('pinData')) if workflow.get('pinData') else None,
    workflow.get('versionId'),
    now,
    WORKFLOW_ID
))

sys.stdout.write(f'Filas afectadas workflow_entity: {cursor.rowcount}\n')
sys.stdout.flush()

# ⚠️ IMPORTANTE: También actualizar shared_workflow si existe
sys.stdout.write('Actualizando shared_workflow...\n')
sys.stdout.flush()
now_shared = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
cursor.execute('''
    UPDATE shared_workflow
    SET updatedAt = ?
    WHERE workflowId = ?
''', (now_shared, WORKFLOW_ID))

sys.stdout.write(f'Filas afectadas shared_workflow: {cursor.rowcount}\n')
sys.stdout.flush()

conn.commit()

# Verificar actualización
cursor.execute('SELECT name, updatedAt FROM workflow_entity WHERE id = ?', (WORKFLOW_ID,))
updated = cursor.fetchone()

sys.stdout.write(f'✅ Workflow actualizado: {updated[0]}\n')
sys.stdout.write(f'   Última actualización: {updated[1]}\n')
sys.stdout.flush()

conn.close()
ENDPYTHON
"

# Limpiar archivo temporal del contenedor
docker exec $N8N_CONTAINER rm -f /tmp/workflow_updated.json

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Workflow actualizado exitosamente"
    echo ""
    echo "📝 Próximos pasos:"
    echo "   1. Accede a n8n: https://n8n-analytics.powersolution.es"
    echo "   2. Abre el workflow '$WORKFLOW_NAME'"
    echo "   3. Verifica que el campo 'projectteamfilter' esté presente en ConfiguracionUsuarios"
    echo "   4. Asigna las credenciales necesarias si es necesario"
    echo "   5. Activa el workflow si está inactivo"
    echo ""
else
    echo ""
    echo "❌ Error al actualizar el workflow"
    exit 1
fi

