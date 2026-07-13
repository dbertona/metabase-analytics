#!/usr/bin/env bash
set -euo pipefail

echo "🛑 Parando Superset..."
docker compose down
echo "✅ Superset parado."
