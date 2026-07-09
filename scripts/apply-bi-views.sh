#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="${ROOT_DIR}/scripts/sql/bi_dashboard_planificacion_views.sql"

echo "==> Aplicando vistas BI (planificación)..."
docker exec -i supabase-db psql -U postgres -d postgres < "${SQL_FILE}"
docker exec -i supabase-db psql -U postgres -d postgres \
  < "${ROOT_DIR}/scripts/sql/mb_dashboard_planificacion_views.sql"
echo "✅ Vistas BI aplicadas"
