#!/bin/bash

# Script para iniciar Metabase con Docker Compose
# Uso: ./scripts/start.sh

set -e

echo "🚀 Iniciando Metabase..."

# Verificar que existe el archivo .env
if [ ! -f .env ]; then
    echo "⚠️  Archivo .env no encontrado. Copiando desde env.example..."
    cp env.example .env
    echo "📝 Por favor, edita el archivo .env con tus configuraciones antes de continuar."
    echo "   Especialmente importante: MB_ENCRYPTION_SECRET_KEY"
    exit 1
fi

# Crear directorios de datos si no existen
mkdir -p data/metabase data/postgres

# Verificar que Docker está corriendo
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker no está corriendo. Por favor, inicia Docker primero."
    exit 1
fi

# Iniciar servicios
echo "🐳 Iniciando contenedores..."
docker compose up -d

# Esperar a que los servicios estén listos
echo "⏳ Esperando a que los servicios estén listos..."
sleep 10

# Verificar estado
echo "📊 Estado de los servicios:"
docker compose ps

echo ""
echo "✅ Metabase iniciado correctamente!"
echo "🌐 Accede a: http://localhost:3000"
echo "📊 Estado: docker compose ps"
echo "📝 Logs: docker compose logs -f"
echo "🛑 Parar: ./scripts/stop.sh"
