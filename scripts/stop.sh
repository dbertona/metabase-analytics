#!/bin/bash

# Script para parar Metabase con Docker Compose
# Uso: ./scripts/stop.sh

set -e

echo "🛑 Parando Metabase..."

# Parar servicios
docker compose down

echo "✅ Metabase parado correctamente!"
echo "📊 Para ver el estado: docker compose ps"
echo "🚀 Para iniciar de nuevo: ./scripts/start.sh"
