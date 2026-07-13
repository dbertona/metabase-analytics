#!/usr/bin/env bash
set -euo pipefail

mkdir -p backups
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="backups/superset_backup_$TIMESTAMP"

echo "💾 Creando backup de Superset..."
mkdir -p "$BACKUP_DIR"

if [ -d "data/superset-home" ]; then
  echo "📁 Copiando data/superset-home..."
  cp -r data/superset-home "$BACKUP_DIR/"
fi

if [ -f ".env" ]; then
  cp .env "$BACKUP_DIR/"
fi

tar -czf "backups/superset_backup_$TIMESTAMP.tar.gz" -C backups "superset_backup_$TIMESTAMP"
rm -rf "$BACKUP_DIR"

echo "✅ Backup: backups/superset_backup_$TIMESTAMP.tar.gz"
