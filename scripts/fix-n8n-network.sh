#!/bin/bash
# =============================================================================
# Script para conectar n8n a la red de Supabase (permanente)
# =============================================================================
# Este script conecta el contenedor n8n a la red ps_admin_default
# para que pueda resolver el hostname "kong" de Supabase.
# =============================================================================

set -euo pipefail

N8N_CONTAINER="n8n"
SUPABASE_NETWORK="ps_admin_default"

echo "🔧 Verificando conexión de n8n a la red de Supabase..."

# Verificar que el contenedor n8n existe y está corriendo
if ! docker ps --format '{{.Names}}' | grep -q "^${N8N_CONTAINER}$"; then
    echo "ℹ️  El contenedor '${N8N_CONTAINER}' no está corriendo en este host — omitiendo (normal en VM Analytics sin n8n local)"
    exit 0
fi

# Verificar que la red existe
if ! docker network ls --format '{{.Name}}' | grep -q "^${SUPABASE_NETWORK}$"; then
    echo "ℹ️  La red '${SUPABASE_NETWORK}' no existe en este host — omitiendo"
    exit 0
fi

# Verificar si ya está conectado
if docker inspect "${N8N_CONTAINER}" --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' | grep -q "${SUPABASE_NETWORK}"; then
    echo "✅ n8n ya está conectado a la red ${SUPABASE_NETWORK}"
else
    echo "📡 Conectando n8n a la red ${SUPABASE_NETWORK}..."
    docker network connect "${SUPABASE_NETWORK}" "${N8N_CONTAINER}" || {
        echo "❌ Error al conectar n8n a la red"
        exit 1
    }
    echo "✅ n8n conectado exitosamente a la red ${SUPABASE_NETWORK}"
fi

# Verificar conectividad
echo "🔍 Verificando conectividad a Supabase..."
if docker exec "${N8N_CONTAINER}" ping -c 1 -W 2 kong >/dev/null 2>&1; then
    echo "✅ n8n puede resolver el hostname 'kong'"
else
    echo "⚠️  Advertencia: n8n no puede resolver 'kong' (puede tardar unos segundos)"
fi

echo "✅ Configuración completada"
