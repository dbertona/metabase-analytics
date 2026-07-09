#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Aplicando capa BI (vistas SQL)..."
bash "${ROOT_DIR}/scripts/apply-bi-views.sh"

echo "==> Levantando Apache Superset (POC)..."
docker compose -f docker-compose.superset.yml build
docker compose -f docker-compose.superset.yml up -d

echo "==> Esperando a que Superset responda en :8088..."
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:${SUPERSET_PORT:-8088}/health" >/dev/null 2>&1; then
    echo "    Superset listo (${i}s)"
    break
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    echo "ERROR: Superset no respondió a tiempo. Revisa: docker compose -f docker-compose.superset.yml logs -f superset"
    exit 1
  fi
done

echo "==> Configurando conexión PS Analytics y dashboard de planificación..."
echo "==> Configurando dashboard (datos PBI + filtros)..."
export SUPERSET_URL="${SUPERSET_URL:-http://localhost:8088}"
export SUPERSET_USER="${SUPERSET_USER:-admin}"
export SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-PsSuperset#2026xK9!}"
python3 scripts/setup-superset-planificacion.py

cat <<'EOF'

══════════════════════════════════════════════════════════════
✅ Superset listo (enfoque mantenible)
══════════════════════════════════════════════════════════════
URL:       http://192.168.36.100:8088
Dashboard: http://192.168.36.100:8088/superset/dashboard/planificacion-ps-analytics/
Usuario:   admin
Password:  PsSuperset#2026xK9!

Fuente de datos (única):
  scripts/sql/bi_dashboard_planificacion_views.sql

KPIs alineados con PBI (año 2026, ambas empresas):
  Obj Facturación 7.400.000 € | Plan Facturación 7.748.763 €
  Obj Crecimiento 7,19 %      | Plan Crecimiento 12,24 %

Regenerar dashboard:
  python3 scripts/setup-superset-planificacion.py
══════════════════════════════════════════════════════════════
EOF
