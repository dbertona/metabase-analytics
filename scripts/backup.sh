#!/bin/bash

# Script para hacer backup de Metabase
# Uso: ./scripts/backup.sh

set -e

# Crear directorio de backups si no existe
mkdir -p backups

# Generar timestamp para el backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="backups/metabase_backup_$TIMESTAMP"

echo "💾 Creando backup de Metabase..."

# Crear directorio de backup
mkdir -p "$BACKUP_DIR"

# Backup de datos de Metabase
if [ -d "data/metabase" ]; then
    echo "📁 Copiando datos de Metabase..."
    cp -r data/metabase "$BACKUP_DIR/"
fi

# Backup de datos de PostgreSQL
if [ -d "data/postgres" ]; then
    echo "🗄️  Copiando datos de PostgreSQL..."
    cp -r data/postgres "$BACKUP_DIR/"
fi

# Backup de configuración
if [ -f ".env" ]; then
    echo "⚙️  Copiando configuración..."
    cp .env "$BACKUP_DIR/"
fi

# Crear archivo comprimido
echo "📦 Comprimiendo backup..."
tar -czf "backups/metabase_backup_$TIMESTAMP.tar.gz" -C backups "metabase_backup_$TIMESTAMP"

# Limpiar directorio temporal
rm -rf "$BACKUP_DIR"

echo "✅ Backup completado: backups/metabase_backup_$TIMESTAMP.tar.gz"
echo "📊 Tamaño del backup: $(du -h "backups/metabase_backup_$TIMESTAMP.tar.gz" | cut -f1)"





