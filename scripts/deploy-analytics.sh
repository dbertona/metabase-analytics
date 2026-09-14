#!/usr/bin/env bash
# Canal único de deploy Analytics (Gitea Actions + CLI), equivalente a
# deploy-timesheet.yml: testing | production. En prod, 004/SQL solo vía gate.
#
# Uso:
#   ./scripts/deploy-analytics.sh --env testing --yes
#   ./scripts/deploy-analytics.sh --env production --yes
#   ./scripts/deploy-analytics.sh --env testing --scope 021 --yes
#   ./scripts/deploy-analytics.sh --env production --scope 004+sql --yes --skip-copy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/scripts/deploy-004-gated.sh"
WF021="$ROOT/scripts/deploy-n8n-workflow-021.sh"

ENV=""
SCOPE="all"
ASSUME_YES=0
SKIP_COPY=0
ALLOW_FIGURE_CHANGE=0
YEAR="${YEAR:-2026}"

usage() {
  cat <<'EOF'
Deploy Analytics (004 + 021 + SQL) a testing o production.

  ./scripts/deploy-analytics.sh --env testing --yes
  ./scripts/deploy-analytics.sh --env production --yes
  ./scripts/deploy-analytics.sh --env testing --scope 021 --yes
  ./scripts/deploy-analytics.sh --env production --scope sql --yes

--scope: all (default) | 004 | sql | 021 | 004+sql
--skip-copy / --allow-figure-change: solo production (se pasan al gate)
--yes: obligatorio en production; en Gitea siempre va.

Testing: aplica artefactos del repo a 103 / :5435 (sin clon, sin canary).
Production: deploy-004-gated.sh --yes (004/SQL) + 021 a n8n-prod si el scope lo incluye.
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="${2:-}"; shift ;;
    --scope) SCOPE="${2:-}"; shift ;;
    --yes|-y) ASSUME_YES=1 ;;
    --skip-copy) SKIP_COPY=1 ;;
    --allow-figure-change) ALLOW_FIGURE_CHANGE=1 ;;
    --year) YEAR="${2:-}"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "❌ Flag desconocido: $1" >&2; usage 1 ;;
  esac
  shift
done

[[ "$ENV" == "testing" || "$ENV" == "production" ]] || {
  echo "❌ Falta --env testing|production" >&2
  usage 1
}

case "$SCOPE" in
  all|004|sql|021|004+sql|sql+004) ;;
  *) echo "❌ --scope inválido: $SCOPE (all|004|sql|021|004+sql)" >&2; exit 1 ;;
esac

[[ -x "$GATE" ]] || chmod +x "$GATE"
[[ -x "$WF021" ]] || chmod +x "$WF021"

SSH_PASS="${SSH_PASS:-${DEPLOY_SSH_PASSWORD:-PsAdmin2025}}"
export SSH_PASS
export DEPLOY_SSH_PASSWORD="${DEPLOY_SSH_PASSWORD:-$SSH_PASS}"
export YEAR

gate_scope_flags() {
  case "$SCOPE" in
    all) ;;
    004) echo --004-only ;;
    sql) echo --sql-only ;;
    021) echo --021-only ;;
    004+sql|sql+004) echo --004-sql ;;
  esac
}

scope_has_021() { [[ "$SCOPE" == "all" || "$SCOPE" == "021" ]]; }
scope_has_gate() { [[ "$SCOPE" != "021" ]]; }

echo "════════════════════════════════════════════════════════════"
echo " Deploy Analytics"
echo " env=${ENV} scope=${SCOPE} year=${YEAR} yes=${ASSUME_YES}"
echo "════════════════════════════════════════════════════════════"

if [[ "$ENV" == "testing" ]]; then
  # shellcheck disable=SC2046
  SSH_PASS="$SSH_PASS" "$GATE" --yes --no-prod --skip-copy --apply-only \
    --year "$YEAR" $(gate_scope_flags)
  echo ""
  echo "✅ Testing actualizado (scope=${SCOPE})."
  echo "   SQL: Analytics :5435  |  n8n: VM 103  |  021 sin cron"
  echo "   No se tocó prod. No se lanzó 004."
  exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo "❌ Production exige --yes (Gitea lo pasa; a mano: confirma el gate)." >&2
  exit 1
fi

if scope_has_gate; then
  extra=()
  [[ "$SKIP_COPY" -eq 1 ]] && extra+=(--skip-copy)
  [[ "$ALLOW_FIGURE_CHANGE" -eq 1 ]] && extra+=(--allow-figure-change)
  # shellcheck disable=SC2046
  SSH_PASS="$SSH_PASS" "$GATE" --yes --year "$YEAR" $(gate_scope_flags) "${extra[@]+"${extra[@]}"}"
fi

if scope_has_021; then
  echo ""
  echo "🩺 Publicando 021 a n8n prod (cron L–V 07:00) ..."
  SSH_PASS="$SSH_PASS" N8N_SSH_PASS="$SSH_PASS" "$WF021" --env production
fi

echo ""
echo "✅ Production actualizado (scope=${SCOPE})."
scope_has_gate && echo "   004/SQL: solo si el gate cerró. No se lanzó 004 en prod."
scope_has_021 && echo "   021: n8n-prod a021healthcheck0001"
echo "   Resync datos: webhook sync-bc-to-analytics (aparte, con OK de prod)."
