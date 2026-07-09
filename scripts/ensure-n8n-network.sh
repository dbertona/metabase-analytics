#!/bin/bash
# =============================================================================
# Script para asegurar que n8n esté conectado a la red de Supabase
# =============================================================================
# Este script verifica y conecta n8n a la red ps_admin_default si no está
# conectado. Se puede ejecutar manualmente o desde cron.
# =============================================================================

set -euo pipefail

N8N_CONTAINER="n8n"
SUPABASE_NETWORK="ps_admin_default"

# Verificar que el contenedor n8n existe y está corriendo
if ! docker ps --format '{{.Names}}' | grep -q "^${N8N_CONTAINER}$"; then
    echo "⚠️  El contenedor '${N8N_CONTAINER}' no está corriendo"
    exit 0  # No es un error si n8n no está corriendo
fi

# Verificar que la red existe
if ! docker network ls --format '{{.Name}}' | grep -q "^${SUPABASE_NETWORK}$"; then
    echo "⚠️  La red '${SUPABASE_NETWORK}' no existe"
    exit 0  # No es un error si la red no existe
fi

# Verificar si ya está conectado
NETWORKS=$(docker inspect "${N8N_CONTAINER}" --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null || echo "")

if echo "$NETWORKS" | grep -q "${SUPABASE_NETWORK}"; then
    # Ya está conectado, verificar conectividad
    if docker exec "${N8N_CONTAINER}" ping -c 1 -W 2 kong >/dev/null 2>&1; then
        exit 0  # Todo bien
    else
        echo "⚠️  n8n está en la red pero no puede resolver 'kong'"
        exit 0  # No es crítico
    fi
else
    # Conectar a la red
    echo "📡 Conectando n8n a la red ${SUPABASE_NETWORK}..."
    if docker network connect "${SUPABASE_NETWORK}" "${N8N_CONTAINER}" 2>/dev/null; then
        echo "✅ n8n conectado a la red ${SUPABASE_NETWORK}"
        # Esperar un momento para que la red se configure
        sleep 2
        # Verificar conectividad
        if docker exec "${N8N_CONTAINER}" ping -c 1 -W 2 kong >/dev/null 2>&1; then
            echo "✅ n8n puede resolver el hostname 'kong'"
        fi
    else
        echo "❌ Error al conectar n8n a la red"
        exit 1
    fi
fi
