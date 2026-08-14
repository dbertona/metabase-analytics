#!/usr/bin/env bash
# Aplica capa BI (bi_mv_* + wrappers bi_v_*) o solo REFRESH de materializadas.
# Opcional: --with-se aplica antes sql/views/seguimiento_economico_views.sql
#
# Uso:
#   ./scripts/apply-bi-views.sh                 # CREATE/REPLACE bi_* (bloqueado en prod)
#   ./scripts/apply-bi-views.sh --with-se       # v_se_* + bi_*
#   ./scripts/apply-bi-views.sh --refresh       # solo REFRESH (prod permitido)
#
# Destino:
#   ANALYTICS_DSN=postgresql://...           # preferido
#   o docker exec supabase-db (en VM 100)
#   o fallback remoto 192.168.36.100:5433 vía contenedor postgres:15
#
# Publicar fórmulas a prod: ./scripts/deploy-004-gated.sh --yes
# Bypass emergencia: ALLOW_DIRECT_SQL_PROD=1
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="${ROOT_DIR}/scripts/sql/bi_dashboard_planificacion_views.sql"
SE_SQL_FILE="${ROOT_DIR}/sql/views/seguimiento_economico_views.sql"
PROD_DSN_FALLBACK="postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres"

REFRESH_ONLY=0
WITH_SE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh) REFRESH_ONLY=1 ;;
    --with-se|--se-views) WITH_SE=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "❌ Flag desconocido: $1" >&2
      exit 1
      ;;
  esac
  shift
done

REFRESH_SQL=$(cat <<'SQL'
REFRESH MATERIALIZED VIEW bi_mv_planificacion_kpi;
REFRESH MATERIALIZED VIEW bi_mv_evolucion_mensual;
REFRESH MATERIALIZED VIEW bi_mv_facturacion_probabilidad;
REFRESH MATERIALIZED VIEW bi_mv_resumen_proyectos;
REFRESH MATERIALIZED VIEW bi_mv_unidad;
REFRESH MATERIALIZED VIEW bi_mv_facturacion;
REFRESH MATERIALIZED VIEW bi_mv_gastos;
REFRESH MATERIALIZED VIEW bi_mv_mano_obra;
SELECT 'bi_mvs_refreshed' AS status;
SQL
)

resolved_dsn() {
  echo "${ANALYTICS_DSN:-${ANALYTICS_DSN_FALLBACK:-$PROD_DSN_FALLBACK}}"
}

analytics_target_is_prod() {
  local dsn
  dsn="$(resolved_dsn)"
  case "$dsn" in
    *192.168.36.103*|*192.168.36.102*|*analytics_testing*|*analytics_dev*)
      return 1
      ;;
    *192.168.36.100*|*SuperSecurePassword2025*)
      return 0
      ;;
  esac
  if [[ -z "${ANALYTICS_DSN:-}" ]] && command -v docker >/dev/null 2>&1 \
     && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'supabase-db'; then
    return 0
  fi
  return 0
}

guard_prod_formula() {
  if [[ "$REFRESH_ONLY" -eq 1 ]]; then
    return 0
  fi
  if [[ "${FIGURES_GATE_OK:-}" == "1" || "${ALLOW_DIRECT_SQL_PROD:-}" == "1" ]]; then
    return 0
  fi
  if analytics_target_is_prod; then
    echo "⛔ Aplicar vistas/MVs a Analytics prod está bloqueado." >&2
    echo "   Publicar cifras: $ROOT_DIR/scripts/deploy-004-gated.sh --yes" >&2
    echo "   Solo SQL:        $ROOT_DIR/scripts/deploy-004-gated.sh --yes --sql-only" >&2
    echo "   Testing:         ANALYTICS_DSN='postgresql://postgres:analytics_testing_2025@192.168.36.103:5435/postgres' $0 --with-se" >&2
    echo "   Emergencia:      ALLOW_DIRECT_SQL_PROD=1 $0" >&2
    exit 1
  fi
}

run_psql() {
  local payload="$1"
  local dsn
  dsn="$(resolved_dsn)"

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

guard_prod_formula

if [[ "$REFRESH_ONLY" -eq 1 ]]; then
  echo "==> REFRESH materializadas bi_mv_*..."
  run_psql "${REFRESH_SQL}"
  echo "✅ bi_mv_* refrescadas"
  exit 0
fi

if [[ "$WITH_SE" -eq 1 ]]; then
  [[ -f "$SE_SQL_FILE" ]] || { echo "❌ Falta $SE_SQL_FILE"; exit 1; }
  echo "==> Aplicando vistas v_se_* ..."
  run_psql "$(cat "${SE_SQL_FILE}")"
  echo "✅ v_se_* aplicadas"
fi

echo "==> Aplicando capa BI (MVs + wrappers bi_v_*)..."
run_psql "$(cat "${SQL_FILE}")"
echo "✅ Capa BI aplicada"
echo "   Tip: tras sync 004 las MVs se refrescan solas; manual: $0 --refresh"
