#!/bin/bash
# Script para actualizar el workflow 004_sync_bc_to_ps_analytics en n8n
# Usa la API REST de n8n (método recomendado para servidores en la nube)
#
# Uso: ./scripts/update-n8n-workflow-004-api.sh
#
# Requisitos:
# - El archivo src/workflows/004_sync_bc_to_ps_analytics.json debe existir
# - Variable de entorno N8N_API_KEY configurada (opcional, puede pedir autenticación)

set -e

WORKFLOW_FILE="src/workflows/004_sync_bc_to_ps_analytics.json"
WORKFLOW_NAME="004_sync_bc_to_ps_analytics"
N8N_URL="https://apps.powersolution.es/n8n"
WORKFLOW_ID="d1f7647e114a486e"

echo "🔧 Actualizando workflow 004 en n8n (método API REST)..."
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

# Verificar el ID declarado en el JSON (informativo)
WORKFLOW_ID_FROM_JSON=$(python3 << 'PYTHON'
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

if [ -n "$WORKFLOW_ID_FROM_JSON" ] && [ "$WORKFLOW_ID_FROM_JSON" != "$WORKFLOW_ID" ]; then
    echo "⚠️  El JSON declara ID '${WORKFLOW_ID_FROM_JSON}', se usará el ID de producción '${WORKFLOW_ID}'."
fi

echo "✅ Workflow ID: $WORKFLOW_ID"
echo ""

# Preparar el payload para la API
# La API de n8n espera el workflow completo
PAYLOAD_FILE="/tmp/workflow_004_payload.json"
python3 -m json.tool "$WORKFLOW_FILE" > "$PAYLOAD_FILE"

echo "📤 Actualizando workflow en n8n..."

# Construir comando curl
if [ -n "$N8N_API_KEY" ]; then
    echo "✅ Usando API key de autenticación"
    CURL_CMD="curl -s -w '\n%{http_code}' -X PUT \"${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}\" \
        -H \"Accept: application/json\" \
        -H \"Content-Type: application/json\" \
        -H \"X-N8N-API-KEY: ${N8N_API_KEY}\" \
        -d @${PAYLOAD_FILE}"
else
    echo "⚠️  No se encontró N8N_API_KEY, intentando sin autenticación..."
    CURL_CMD="curl -s -w '\n%{http_code}' -X PUT \"${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}\" \
        -H \"Accept: application/json\" \
        -H \"Content-Type: application/json\" \
        -d @${PAYLOAD_FILE}"
fi

# Ejecutar actualización
RESPONSE=$(eval "$CURL_CMD" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Verificar resultado
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo ""
    echo "✅ Workflow actualizado exitosamente"
    echo ""

    # Mostrar información del workflow actualizado
    WORKFLOW_NAME_UPDATED=$(echo "$BODY" | python3 -c "import json, sys; print(json.load(sys.stdin).get('name', 'desconocido'))" 2>/dev/null || echo "desconocido")
    WORKFLOW_UPDATED_AT=$(echo "$BODY" | python3 -c "import json, sys; print(json.load(sys.stdin).get('updatedAt', 'desconocido'))" 2>/dev/null || echo "desconocido")

    echo "   Nombre: ${WORKFLOW_NAME_UPDATED}"
    echo "   ID: ${WORKFLOW_ID}"
    echo "   Actualizado: ${WORKFLOW_UPDATED_AT}"
    echo ""
    echo "📝 Próximos pasos:"
    echo "   1. Accede a n8n: ${N8N_URL}"
    echo "   2. Abre el workflow '${WORKFLOW_NAME}'"
    echo "   3. Verifica que el campo 'projectteamfilter' esté presente en ConfiguracionUsuarios"
    echo "   4. Asigna las credenciales necesarias si es necesario"
    echo "   5. Activa el workflow si está inactivo"
    echo ""

    # Limpiar archivo temporal
    rm -f "$PAYLOAD_FILE"
    exit 0
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "❌ Error de autenticación (HTTP ${HTTP_CODE})"
    echo "⚠️  Necesitas configurar N8N_API_KEY:"
    echo "   export N8N_API_KEY='tu_api_key_aqui'"
    echo "   ${0}"
    rm -f "$PAYLOAD_FILE"
    exit 1
elif [ "$HTTP_CODE" = "404" ]; then
    echo "❌ Error: Workflow no encontrado (HTTP ${HTTP_CODE})"
    echo "   Verifica que el workflow ID sea correcto: ${WORKFLOW_ID}"
    rm -f "$PAYLOAD_FILE"
    exit 1
else
    echo "❌ Error al actualizar el workflow (HTTP ${HTTP_CODE})"
    echo "Respuesta:"
    echo "$BODY" | head -20
    echo ""
    rm -f "$PAYLOAD_FILE"
    exit 1
fi


