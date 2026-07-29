#!/usr/bin/env bash
# Aplica capa BI (bi_mv_* + wrappers bi_v_*) o solo REFRESH de materializadas.
# Uso:
#   ./scripts/apply-bi-views.sh              # CREATE/REPLACE desde SQL
#   ./scripts/apply-bi-views.sh --refresh    # REFRESH tras sync (sin recrear)
#
# Destino:
#   ANALYTICS_DSN=postgresql://...           # preferido
#   o docker exec supabase-db (en VM 100)
#   o fallback remoto 192.168.36.100:5433 vía contenedor postgres:15
set -euo pipefail
# macOS agentes: asegurar psql/docker en PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="${ROOT_DIR}/scripts/sql/bi_dashboard_planificacion_views.sql"

REFRESH_SQL=$(cat <<'SQL'
REFRESH MATERIALIZED VIEW bi_mv_planificacion_kpi;
REFRESH MATERIALIZED VIEW bi_mv_evolucion_mensual;
REFRESH MATERIALIZED VIEW bi_mv_facturacion_probabilidad;
REFRESH MATERIALIZED VIEW bi_mv_resumen_proyectos;
REFRESH MATERIALIZED VIEW bi_mv_unidad;
REFRESH MATERIALIZED VIEW bi_mv_facturacion;
SELECT 'bi_mvs_refreshed' AS status;
SQL
)

run_psql() {
  local payload="$1"
  local dsn="${ANALYTICS_DSN:-${ANALYTICS_DSN_FALLBACK:-postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres}}"

  if command -v psql >/dev/null 2>&1; then
    echo "==> Destino: psql → ${dsn%%@*}@***"
    printf '%s\n' "${payload}" | psql "${dsn}" -v ON_ERROR_STOP=1
  elif [[ -n "${ANALYTICS_DSN:-}" ]]; then
    printf '%s\n' "${payload}" | docker run --rm -i --network host postgres:15 \
      psql "${ANALYTICS_DSN}" -v ON_ERROR_STOP=1
  elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'supabase-db'; then
    printf '%s\n' "${payload}" | docker exec -i supabase-db \
      psql -U postgres -d postgres -v ON_ERROR_STOP=1
  elif command -v docker >/dev/null 2>&1; then
    echo "==> Destino remoto (docker postgres:15): ${dsn%%@*}@***"
    printf '%s\n' "${payload}" | docker run --rm -i --network host postgres:15 \
      psql "${dsn}" -v ON_ERROR_STOP=1
  else
    echo "❌ Ni psql ni docker disponibles. Exporta ANALYTICS_DSN y usa psql, o ejecuta en VM 100."
    exit 1
  fi
}

if [[ "${1:-}" == "--refresh" ]]; then
  echo "==> REFRESH materializadas bi_mv_*..."
  run_psql "${REFRESH_SQL}"
  echo "✅ bi_mv_* refrescadas"
  exit 0
fi

echo "==> Aplicando capa BI (MVs + wrappers bi_v_*)..."
run_psql "$(cat "${SQL_FILE}")"
echo "✅ Capa BI aplicada"
echo "   Tip: tras sync 004 las MVs se refrescan solas; manual: $0 --refresh"
