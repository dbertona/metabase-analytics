#!/usr/bin/env bash
# DEPRECADO — el gate de cifras (clon / canary / waits / compare) se retiró.
# Redirige a deploy-analytics.sh (apply directo desde el repo).
#
# Compat flags:
#   --yes --004-only / --sql-only / --004-sql / --021-only
#   --no-prod → --env testing
#   --skip-copy / --allow-figure-change / --apply-only → no-op con aviso
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY="$ROOT/scripts/deploy-analytics.sh"

ENV="production"
SCOPE="all"
ASSUME_YES=0
YEAR="${YEAR:-2026}"
EXTRA=()

echo "⚠️  deploy-004-gated.sh está deprecado (sin canary/clon/wait)."
echo "   Usar: ./scripts/deploy-analytics.sh --env production|testing --yes"
echo "   Redirigiendo..."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --no-prod) ENV="testing" ;;
    --004-only) SCOPE="004" ;;
    --sql-only) SCOPE="sql" ;;
    --004-sql) SCOPE="004+sql" ;;
    --021-only) SCOPE="021" ;;
    --apply-only)
      ENV="testing"
      echo "ℹ️  --apply-only → testing apply (compat)."
      ;;
    --skip-copy)
      echo "ℹ️  --skip-copy ignorado (gate retirado)."
      ;;
    --allow-figure-change)
      echo "ℹ️  --allow-figure-change ignorado (gate retirado)."
      ;;
    --year) YEAR="${2:-}"; shift ;;
    -h|--help)
      cat <<'EOF'
Deprecado. Equivalente:

  ./scripts/deploy-004-gated.sh --yes
    → ./scripts/deploy-analytics.sh --env production --yes

  ./scripts/deploy-004-gated.sh --yes --no-prod --apply-only
    → ./scripts/deploy-analytics.sh --env testing --yes

  --004-only / --sql-only / --021-only / --004-sql → --scope
EOF
      exit 0
      ;;
    *)
      echo "⚠️  Flag ignorado en stub: $1"
      ;;
  esac
  shift
done

[[ -x "$DEPLOY" ]] || chmod +x "$DEPLOY"

args=(--env "$ENV" --scope "$SCOPE" --year "$YEAR")
[[ "$ASSUME_YES" -eq 1 ]] && args+=(--yes)

exec "$DEPLOY" "${args[@]}"
