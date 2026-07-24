#!/bin/bash
# Script para descargar el workflow 004 desde n8n
# Basado en: docs/shared/n8n/n8n-integration-guide.md

N8N_URL="https://apps.powersolution.es/n8n"
WORKFLOW_ID="d1f7647e114a486e"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${ROOT_DIR}/src/workflows/004_sync_bc_to_ps_analytics.json"

echo "Descargando workflow 004 desde n8n..."
echo "URL: ${N8N_URL}"
echo "Workflow ID: ${WORKFLOW_ID}"

# Verificar si hay API key configurado
if [ -z "$N8N_API_KEY" ]; then
  echo "⚠️  No se encontró N8N_API_KEY en variables de entorno"
  echo "   Intentando descargar sin autenticación..."
  CURL_CMD="curl -s -w \"\n%{http_code}\" -X GET \"${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\""
else
  echo "✅ Usando API key de autenticación"
  CURL_CMD="curl -s -w \"\n%{http_code}\" -X GET \"${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -H \"X-N8N-API-KEY: ${N8N_API_KEY}\""
fi

# Descargar workflow usando la API de n8n
# Según la guía: curl -X GET "http://.../api/v1/workflows/WORKFLOW_ID" -H "X-N8N-API-KEY: ..."
RESPONSE=$(eval "$CURL_CMD" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Verificar código HTTP
if [ "$HTTP_CODE" = "200" ]; then
  # Guardar workflow
  echo "$BODY" > "${OUTPUT_FILE}"

  # Validar JSON
  if python3 -m json.tool "${OUTPUT_FILE}" > /dev/null 2>&1; then
    # Formatear JSON
    python3 -m json.tool "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    echo "✅ Workflow descargado exitosamente en: ${OUTPUT_FILE}"

    # Mostrar información básica
    WORKFLOW_NAME=$(python3 -c "import json; print(json.load(open('${OUTPUT_FILE}'))['name'])" 2>/dev/null || echo "desconocido")
    echo "   Nombre: ${WORKFLOW_NAME}"
    echo "   ID: ${WORKFLOW_ID}"
  else
    echo "❌ Error: El JSON descargado no es válido"
    echo "Respuesta recibida:"
    echo "$BODY" | head -20
    rm -f "${OUTPUT_FILE}"
    exit 1
  fi
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  echo "❌ Error de autenticación (HTTP ${HTTP_CODE})"
  echo "⚠️  Necesitas configurar N8N_API_KEY:"
  echo "   export N8N_API_KEY='tu_api_key_aqui'"
  echo "   ${0}"
  exit 1
elif [ "$HTTP_CODE" = "404" ]; then
  echo "❌ Error: Workflow no encontrado (HTTP ${HTTP_CODE})"
  echo "   Verifica que el workflow ID sea correcto: ${WORKFLOW_ID}"
  exit 1
else
  echo "❌ Error al descargar el workflow (HTTP ${HTTP_CODE})"
  echo "Respuesta:"
  echo "$BODY" | head -20
  echo ""
  echo "⚠️  Intenta descargarlo manualmente desde:"
  echo "   ${N8N_URL}/workflow/${WORKFLOW_ID}"
  exit 1
fi


