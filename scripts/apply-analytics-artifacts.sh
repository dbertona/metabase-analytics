#!/usr/bin/env bash
# Aplica artefactos Analytics (004 / 021 / SQL) a testing o production.
# Invocado por deploy-analytics.sh. No clona, no canary, no compara cifras.
#
# Uso:
#   ./scripts/apply-analytics-artifacts.sh --env testing --scope all
#   ./scripts/apply-analytics-artifacts.sh --env production --scope 004+sql
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

resolve_apps_root() {
  local c
  for c in \
    "${APPS_ROOT:-}" \
    "${GITHUB_WORKSPACE:-}/_apps" \
    "${GITHUB_WORKSPACE:-}/power-solution-apps" \
    "$ROOT/../power-solution-apps" \
    "$ROOT/../../power-solution-apps" \
    "/opt/power-solution-apps" \
    "/Users/marcelodanielbertona/POWER-SOLUTION-PROJECTS/power-solution-apps"
  do
    if [[ -n "$c" && -f "$c/scripts/update-n8n-workflow-postgres-remote.sh" ]]; then
      APPS_ROOT="$c"
      return 0
    fi
  done
  echo "❌ No encuentro power-solution-apps (update-n8n-workflow-postgres-remote.sh)." >&2
  exit 1
}
resolve_apps_root

WF_004="$ROOT/src/workflows/004_sync_bc_to_ps_analytics.json"
WF_021="$ROOT/src/workflows/021_health_check_analytics_bc.json"
APPLY_BI="$ROOT/scripts/apply-bi-views.sh"

SSH_USER="${SSH_USER:-ps_admin}"
SSH_PASS="${SSH_PASS:-${DEPLOY_SSH_PASSWORD:-PsAdmin2025}}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=20)

N8N_TESTING_HOST="${N8N_TESTING_HOST:-192.168.36.103}"
N8N_TESTING_APP="${N8N_TESTING_APP:-n8n}"
N8N_TESTING_PG="${N8N_TESTING_PG:-supabase-db}"
WF_004_TESTING="${WF_004_TESTING:-dlekAIp9f5FsdfJj}"
WF_021_ID="${WF_021_ID:-a021healthcheck0001}"
N8N_TESTING_PROJECT_ID="${N8N_TESTING_PROJECT_ID:-4AwsO1IPiJcgJ2tj}"

N8N_PROD_HOST="${N8N_PROD_HOST:-192.168.36.101}"
N8N_PROD_APP="${N8N_PROD_APP:-n8n-prod}"
N8N_PROD_PG="${N8N_PROD_PG:-supabase-db}"
WF_004_PROD="${WF_004_PROD:-d1f7647e114a486e}"

ANALYTICS_TESTING_DSN="${ANALYTICS_TESTING_DSN:-postgresql://postgres:analytics_testing_2025@192.168.36.103:5435/postgres}"
ANALYTICS_PROD_DSN="${ANALYTICS_PROD_DSN:-postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres}"

ENV=""
SCOPE="all"

usage() {
  sed -n '2,10p' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="${2:-}"; shift ;;
    --scope) SCOPE="${2:-}"; shift ;;
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
  all|004|sql|021|004+sql|sql+004|004sql) ;;
  *) echo "❌ --scope inválido: $SCOPE" >&2; exit 1 ;;
esac

# Normalizar alias del gate antiguo
[[ "$SCOPE" == "004sql" ]] && SCOPE="004+sql"

scope_has_004() { [[ "$SCOPE" == "all" || "$SCOPE" == "004" || "$SCOPE" == "004+sql" || "$SCOPE" == "sql+004" ]]; }
scope_has_sql() { [[ "$SCOPE" == "all" || "$SCOPE" == "sql" || "$SCOPE" == "004+sql" || "$SCOPE" == "sql+004" ]]; }
scope_has_021() { [[ "$SCOPE" == "all" || "$SCOPE" == "021" ]]; }

ssh_testing() { sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$N8N_TESTING_HOST" "$@"; }

export ANALYTICS_DEPLOY_OK=1
export FIGURES_GATE_OK=1
export SSH_PASS
export DEPLOY_SSH_PASSWORD="${DEPLOY_SSH_PASSWORD:-$SSH_PASS}"

seatbelt_004() {
  echo "🔒 Seatbelt estático Transform PlanificacionMes ..."
  python3 - "$WF_004" <<'PY'
import json, sys
path = sys.argv[1]
wf = json.load(open(path, encoding="utf-8"))
if isinstance(wf, list):
    wf = wf[0]
node = next((n for n in wf.get("nodes", []) if n.get("name") == "Transform PlanificacionMes"), None)
if not node:
    raise SystemExit("No está el nodo Transform PlanificacionMes")
code = node.get("parameters", {}).get("jsCode") or ""
banned = ("pbiKey", "keep: 'exact'", 'keep: "exact"')
hits = [b for b in banned if b in code]
if hits:
    raise SystemExit(f"Distinct/PBI en PlanificacionMes: {hits}")
if "e.invoice +=" not in code and "invoice +=" not in code:
    raise SystemExit("PlanificacionMes no agrega invoice (falta SUM)")
print("OK: SUM_REPO (sin pbiKey / exact Distinct)")
PY
}

disable_021_schedule() {
  local src="$1" dest="$2"
  python3 - "$src" "$dest" <<'PY'
import json, sys
src, dest = sys.argv[1:3]
wf = json.load(open(src, encoding="utf-8"))
root = wf[0] if isinstance(wf, list) else wf
n = 0
for node in root.get("nodes", []):
    if node.get("type") == "n8n-nodes-base.scheduleTrigger":
        node["disabled"] = True
        n += 1
if n == 0:
    raise SystemExit("021: no hay scheduleTrigger que desactivar")
json.dump(wf, open(dest, "w", encoding="utf-8"), ensure_ascii=False)
print(f"021 testing: disabled {n} schedule trigger(s) → {dest}")
PY
}

assert_resident_not_pinned() {
  local wf_id="$1" json_path="$2"
  if [[ "$wf_id" != "$WF_004_TESTING" && "$wf_id" != "$WF_021_ID" ]]; then
    return 0
  fi
  if grep -q "String('Production')" "$json_path"; then
    echo "❌ Rechazado: el workflow de pruebas ${wf_id} no puede llevar Production fijo." >&2
    exit 1
  fi
}

apply_n8n_postgres() {
  local host="$1" app="$2" pg="$3" wf_id="$4" json_path="$5"
  if [[ "$host" == "$N8N_TESTING_HOST" ]]; then
    assert_resident_not_pinned "$wf_id" "$json_path"
  fi
  ANALYTICS_DEPLOY_OK=1 FIGURES_GATE_OK=1 \
  DEPLOY_HOST_IP="$host" \
  DEPLOY_SSH_PASSWORD="$SSH_PASS" \
  DEPLOY_SSH_USER="$SSH_USER" \
  N8N_APP_CONTAINER="$app" \
  N8N_PG_CONTAINER="$pg" \
    "$APPS_ROOT/scripts/update-n8n-workflow-postgres-remote.sh" "$wf_id" "$json_path"
}

ensure_021_testing() {
  local pinned="$1"
  echo "🩺 Asegurando 021 en n8n testing (remap creds desde 004) ..."
  local remote_dir="/tmp/n8n-021-apply-$$"
  ssh_testing "mkdir -p '$remote_dir'"
  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
    "$pinned" \
    "$APPS_ROOT/scripts/update_n8n_workflow_postgres.py" \
    "$APPS_ROOT/scripts/remap_n8n_credentials.py" \
    "$SSH_USER@$N8N_TESTING_HOST:$remote_dir/"
  ssh_testing bash -s <<REMOTE
set -euo pipefail
REMOTE_DIR='$remote_dir'
export N8N_DB_PASSWORD
N8N_DB_PASSWORD=\$(docker exec '${N8N_TESTING_APP}' printenv N8N_DB_PASSWORD || docker exec '${N8N_TESTING_APP}' printenv DB_POSTGRESDB_PASSWORD)
export N8N_PG_CONTAINER='${N8N_TESTING_PG}'
export WF_021_ID='${WF_021_ID}'
export DONOR_ID='${WF_004_TESTING}'
export PROJECT_ID='${N8N_TESTING_PROJECT_ID}'
cd "\$REMOTE_DIR"
python3 - <<'PY'
import json, os, uuid
from datetime import datetime, timezone
from pathlib import Path
import sys
sys.path.insert(0, ".")
from remap_n8n_credentials import patch_node_credentials
from update_n8n_workflow_postgres import update_workflow, sql_json, psql_query, psql_exec

WF_ID = os.environ["WF_021_ID"]
DONOR = os.environ["DONOR_ID"]
PROJECT_ID = os.environ["PROJECT_ID"]
path = Path("021_health_check_analytics_bc.json")
if not path.exists():
    cands = list(Path(".").glob("*021*"))
    path = cands[0]
wf = json.loads(path.read_text(encoding="utf-8"))
if isinstance(wf, list):
    wf = wf[0]

def nodes_of(wid):
    raw = psql_query(
        "SELECT nodes::text FROM workflow_history WHERE \\"versionId\\"="
        f"(SELECT \\"activeVersionId\\" FROM workflow_entity WHERE id='{wid}');"
    )
    return json.loads(raw)

donor = nodes_of(DONOR)
m, n, warnings = patch_node_credentials(wf["nodes"], donor, by_credential_name=True)
print(f"021 remap from 004: {m+n} node(s), warnings={len(warnings)}")
for w in warnings:
    print(f"  ⚠️  {w}")

exists = psql_query(f"SELECT id FROM workflow_entity WHERE id = '{WF_ID}'")
if exists:
    vid = update_workflow(WF_ID, wf)
    psql_exec(f"UPDATE workflow_entity SET active = true WHERE id = '{WF_ID}';")
    print(f"021 updated activeVersionId={vid}")
else:
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    hist_now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    new_version = str(uuid.uuid4())
    name = (wf.get("name") or "021 - Health Check Analytics vs BC").replace("'", "''")
    nodes = sql_json(wf.get("nodes", []))
    conns = sql_json(wf.get("connections", {}))
    settings = sql_json(wf.get("settings") or {})
    psql_exec(f"""
BEGIN;
INSERT INTO workflow_entity (
  id, name, active, nodes, connections, "createdAt", "updatedAt",
  settings, "staticData", "pinData", "versionId", "triggerCount",
  meta, "isArchived", "versionCounter", "nodeGroups"
) VALUES (
  '{WF_ID}', '{name}', true,
  '{nodes}'::json, '{conns}'::json,
  '{now}', '{now}', '{settings}'::json,
  NULL, NULL, '{new_version}', 1,
  '{{"templateCredsSetupCompleted": true}}'::json,
  false, 1, '[]'::json
);
INSERT INTO workflow_history (
  "versionId", "workflowId", authors, "createdAt", "updatedAt",
  nodes, connections, name, autosaved, description, "nodeGroups"
) VALUES (
  '{new_version}', '{WF_ID}', 'apply-analytics-artifacts.sh',
  '{hist_now}', '{hist_now}',
  '{nodes}'::json, '{conns}'::json,
  'Version {new_version[:8]}', false, NULL, '[]'::json
);
UPDATE workflow_entity SET "activeVersionId" = '{new_version}', active = true
WHERE id = '{WF_ID}';
INSERT INTO shared_workflow ("workflowId", "projectId", role, "createdAt", "updatedAt")
VALUES ('{WF_ID}', '{PROJECT_ID}', 'workflow:owner', '{hist_now}', '{hist_now}')
ON CONFLICT ("workflowId", "projectId") DO NOTHING;
COMMIT;
""")
    print(f"021 created {WF_ID}")
PY
rm -rf "\$REMOTE_DIR"
REMOTE
}

restart_n8n_testing() {
  echo "🔄 Restart n8n testing (registrar webhooks) ..."
  ssh_testing "docker restart $N8N_TESTING_APP"
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sf -m 5 "http://${N8N_TESTING_HOST}:5678/healthz" >/dev/null 2>&1 \
       || curl -sf -m 5 "http://${N8N_TESTING_HOST}:5678/" >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
}

[[ -f "$WF_004" ]] || { echo "❌ Falta $WF_004"; exit 1; }
[[ -f "$WF_021" ]] || { echo "❌ Falta $WF_021"; exit 1; }
[[ -x "$APPLY_BI" ]] || chmod +x "$APPLY_BI"

echo "════════════════════════════════════════════════════════════"
echo " Apply Analytics artifacts"
echo " env=${ENV} scope=${SCOPE}"
echo "════════════════════════════════════════════════════════════"

scope_has_004 && seatbelt_004

if [[ "$ENV" == "testing" ]]; then
  TMPDIR_APPLY="$(mktemp -d /tmp/analytics-apply.XXXXXX)"
  trap 'rm -rf "$TMPDIR_APPLY"' EXIT
  if scope_has_sql; then
    echo "🧮 Aplicando v_se_* + bi_* en Analytics testing ..."
    ANALYTICS_DSN="$ANALYTICS_TESTING_DSN" "$APPLY_BI" --with-se
  fi
  if scope_has_004; then
    apply_n8n_postgres "$N8N_TESTING_HOST" "$N8N_TESTING_APP" "$N8N_TESTING_PG" \
      "$WF_004_TESTING" "$WF_004"
  fi
  if scope_has_021; then
    disable_021_schedule "$WF_021" "$TMPDIR_APPLY/021.testing.json"
    ensure_021_testing "$TMPDIR_APPLY/021.testing.json"
  fi
  if scope_has_004 || scope_has_021; then
    restart_n8n_testing
  fi
  echo ""
  echo "✅ Testing apply OK (scope=${SCOPE})."
  scope_has_021 && echo "   021 testing sin cron (solo webhook)."
  exit 0
fi

# production
if scope_has_sql; then
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo " HARD STOP prod: aplicar v_se_* + bi_* a Analytics VM 100"
  echo " Impacto: cambia fórmulas publicadas (Apps/PBI)."
  echo "════════════════════════════════════════════════════════════"
  ANALYTICS_DEPLOY_OK=1 FIGURES_GATE_OK=1 ANALYTICS_DSN="$ANALYTICS_PROD_DSN" \
    "$APPLY_BI" --with-se
fi

if scope_has_004; then
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo " HARD STOP prod: aplicar JSON repo a n8n-prod ${WF_004_PROD}"
  echo " Impacto: cambia el workflow 004 en VM 101. NO lanza sync."
  echo "════════════════════════════════════════════════════════════"
  apply_n8n_postgres "$N8N_PROD_HOST" "$N8N_PROD_APP" "$N8N_PROD_PG" \
    "$WF_004_PROD" "$WF_004"
fi

echo ""
echo "✅ Production apply OK (scope=${SCOPE}). NO se lanzó 004."
