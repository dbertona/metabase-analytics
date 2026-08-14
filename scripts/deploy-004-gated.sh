#!/usr/bin/env bash
# Gate de publicación 004 → n8n prod.
#
# 1) Seatbelt estático (Distinct / pbiKey en Transform PlanificacionMes)
# 2) Copia Analytics prod → testing (solo 103)
# 3) Aplica JSON repo a n8n testing (004 + 021), pin BC=Production
# 4) Reset watermarks en testing + canary 004 (psi + pslab)
# 5) 021 en testing: tipo_p_planif_sum / tipo_r_sum / tipo_p_expediente_sum
# 6) Si cierran (tol 0,50 €) → aplica el MISMO JSON repo a n8n prod
#
# NO lanza 004 en prod. NO cambia BC_ENVIRONMENT del contenedor testing.
#
# Uso:
#   ./scripts/deploy-004-gated.sh --yes
#   ./scripts/deploy-004-gated.sh --yes --no-prod
#   ./scripts/deploy-004-gated.sh --yes --skip-copy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPS_ROOT="${APPS_ROOT:-$(cd "$ROOT/../../power-solution-apps" 2>/dev/null && pwd || true)}"
if [[ -z "${APPS_ROOT}" || ! -d "$APPS_ROOT/scripts" ]]; then
  APPS_ROOT="/Users/marcelodanielbertona/POWER-SOLUTION-PROJECTS/power-solution-apps"
fi

WF_004="$ROOT/src/workflows/004_sync_bc_to_ps_analytics.json"
WF_021="$ROOT/src/workflows/021_health_check_analytics_bc.json"

SSH_USER="${SSH_USER:-ps_admin}"
SSH_PASS="${SSH_PASS:-PsAdmin2025}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=20)

N8N_TESTING_HOST="${N8N_TESTING_HOST:-192.168.36.103}"
N8N_TESTING_APP="${N8N_TESTING_APP:-n8n}"
N8N_TESTING_PG="${N8N_TESTING_PG:-supabase-db}"
ANALYTICS_TESTING_CONTAINER="${ANALYTICS_TESTING_CONTAINER:-supabase-analytics-db-testing}"
WF_004_TESTING="${WF_004_TESTING:-dlekAIp9f5FsdfJj}"
WF_021_ID="${WF_021_ID:-a021healthcheck0001}"
N8N_TESTING_PROJECT_ID="${N8N_TESTING_PROJECT_ID:-4AwsO1IPiJcgJ2tj}"
N8N_TESTING_WEBHOOK="${N8N_TESTING_WEBHOOK:-http://192.168.36.103:5678/webhook}"

N8N_PROD_HOST="${N8N_PROD_HOST:-192.168.36.101}"
N8N_PROD_APP="${N8N_PROD_APP:-n8n-prod}"
N8N_PROD_PG="${N8N_PROD_PG:-supabase-db}"
WF_004_PROD="${WF_004_PROD:-d1f7647e114a486e}"

YEAR="${YEAR:-2026}"
ASSUME_YES=0
APPLY_PROD=1
SKIP_COPY=0
CANARY_TIMEOUT_SEC="${CANARY_TIMEOUT_SEC:-2700}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-1200}"

MONEY_CHECKS=(tipo_p_planif_sum tipo_r_sum tipo_p_expediente_sum)
COMPANIES_SQL="'Power Solution Iberia SL','PS LAB CONSULTING SL'"

usage() {
  cat <<'EOF'
Gate 004: clona Analytics prod→testing, canary 004+021, publica JSON a n8n prod.

  ./scripts/deploy-004-gated.sh --yes
  ./scripts/deploy-004-gated.sh --yes --no-prod
  ./scripts/deploy-004-gated.sh --yes --skip-copy
  ./scripts/deploy-004-gated.sh --yes --year 2026

No lanza 004 en prod. No cambia BC_ENVIRONMENT del contenedor testing.
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --no-prod) APPLY_PROD=0 ;;
    --apply-prod) APPLY_PROD=1 ;;
    --skip-copy) SKIP_COPY=1 ;;
    --year) YEAR="$2"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "❌ Flag desconocido: $1" >&2; usage 1 ;;
  esac
  shift
done

ssh_testing() { sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$N8N_TESTING_HOST" "$@"; }

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

pin_bc_production() {
  local src="$1" dest="$2"
  python3 - "$src" "$dest" "$YEAR" <<'PY'
import json, sys
src, dest, year = sys.argv[1:4]
wf = json.load(open(src, encoding="utf-8"))
text = json.dumps(wf, ensure_ascii=False)
text = text.replace("$env.BC_ENVIRONMENT", "'Production'")
text = text.replace(
    "const year = new Date().getUTCFullYear();",
    f"const year = {int(year)};",
)
open(dest, "w", encoding="utf-8").write(text)
print(f"pin BC=Production year={year} → {dest}")
PY
}

apply_n8n_postgres() {
  local host="$1" app="$2" pg="$3" wf_id="$4" json_path="$5"
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
  local remote_dir="/tmp/n8n-021-gate-$$"
  ssh_testing "mkdir -p '$remote_dir'"
  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
    "$pinned" \
    "$APPS_ROOT/scripts/update_n8n_workflow_postgres.py" \
    "$APPS_ROOT/scripts/remap_n8n_credentials.py" \
    "$SSH_USER@$N8N_TESTING_HOST:$remote_dir/"
  ssh_testing bash -s <<REMOTE
set -euo pipefail
REMOTE_DIR='$remote_dir'
WF_021_ID='$WF_021_ID'
DONOR_ID='$WF_004_TESTING'
PROJECT_ID='$N8N_TESTING_PROJECT_ID'
APP='$N8N_TESTING_APP'
PG='$N8N_TESTING_PG'
export N8N_DB_PASSWORD
N8N_DB_PASSWORD=\$(docker exec "\$APP" printenv N8N_DB_PASSWORD || docker exec "\$APP" printenv DB_POSTGRESDB_PASSWORD)
export N8N_PG_CONTAINER="\$PG"
export WF_021_ID='$WF_021_ID'
export DONOR_ID='$WF_004_TESTING'
export PROJECT_ID='$N8N_TESTING_PROJECT_ID'
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
  '{new_version}', '{WF_ID}', 'deploy-004-gated.sh',
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

reset_testing_watermarks() {
  echo "🧹 Reset watermarks testing (canary debe redescubrir ${YEAR}) ..."
  ssh_testing "docker exec $ANALYTICS_TESTING_CONTAINER psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"
UPDATE sync_state SET last_sync_at = '1900-01-01'
WHERE company_name IN ($COMPANIES_SQL)
  AND entity IN (
    'bc_job_planning_line',
    'bc_job_ledger_entry_month',
    'bc_job_ledger_cert_open',
    'bc_expediente_mes',
    'bc_meses_cerrados'
  );
SELECT company_name, entity, last_sync_at
FROM sync_state
WHERE company_name IN ($COMPANIES_SQL)
  AND entity IN (
    'bc_job_planning_line',
    'bc_job_ledger_entry_month',
    'bc_job_ledger_cert_open',
    'bc_expediente_mes',
    'bc_meses_cerrados'
  )
ORDER BY 1, 2;
\""
}

company_name_for() {
  case "$1" in
    psi) echo "Power Solution Iberia SL" ;;
    pslab) echo "PS LAB CONSULTING SL" ;;
    *) echo "$1" ;;
  esac
}

fire_004_canary() {
  local slug="$1"
  local body
  body="$(python3 -c "import json; print(json.dumps({
    'entities': ['planificacion_mes','movimientos_proyectos','expediente_mes','meses_cerrados'],
    'sinceYear': int('$YEAR'),
    'untilYear': int('$YEAR'),
    'reason': 'gate-004-canary-testing'
  }))")"
  echo "🚀 Canary 004 testing company=${slug} year=${YEAR} ..."
  curl -sS -m 15 -X POST \
    "${N8N_TESTING_WEBHOOK}/sync-bc-to-analytics?company=${slug}" \
    -H "Content-Type: application/json" \
    -d "$body" >/tmp/gate-004-${slug}.out 2>/tmp/gate-004-${slug}.err || true
}

wait_004_company() {
  local slug="$1" started="$2"
  local name status elapsed=0
  name="$(company_name_for "$slug")"
  echo "⏳ Esperando 004 ${slug} (${name}) ..."
  while (( elapsed < CANARY_TIMEOUT_SEC )); do
    status="$(ssh_testing "docker exec $ANALYTICS_TESTING_CONTAINER psql -U postgres -d postgres -tAc \"
SELECT COALESCE(status,'') FROM sync_executions
WHERE company_name = '${name}'
  AND started_at >= TIMESTAMPTZ '${started}'
ORDER BY id DESC LIMIT 1;
\"" | tr -d '[:space:]')"
    case "$status" in
      ok)
        echo "✅ 004 ${slug}: ok"
        return 0
        ;;
      error|partial_error|failed)
        echo "❌ 004 ${slug}: ${status}" >&2
        ssh_testing "docker exec $ANALYTICS_TESTING_CONTAINER psql -U postgres -d postgres -c \"
SELECT id, status, started_at, finished_at, left(coalesce(details::text,''), 400)
FROM sync_executions
WHERE company_name = '${name}' AND started_at >= TIMESTAMPTZ '${started}'
ORDER BY id DESC LIMIT 3;
\"" || true
        return 1
        ;;
      running|"")
        sleep 20
        elapsed=$((elapsed + 20))
        ;;
      *)
        sleep 20
        elapsed=$((elapsed + 20))
        ;;
    esac
  done
  echo "❌ Timeout canary 004 ${slug} (${CANARY_TIMEOUT_SEC}s) status='${status}'" >&2
  return 1
}

fire_021() {
  echo "🩺 Lanzando 021 testing ..."
  curl -sS -m 30 -X POST \
    "${N8N_TESTING_WEBHOOK}/analytics-health-check" \
    -H "Content-Type: application/json" \
    -d "{\"year\": ${YEAR}}" >/tmp/gate-021.out 2>/tmp/gate-021.err || true
}

wait_021_money() {
  local started="$1"
  local elapsed=0 rows fails
  echo "⏳ Esperando 6 checks de dinero 021 (checked_at >= ${started}) ..."
  while (( elapsed < HEALTH_TIMEOUT_SEC )); do
    rows="$(ssh_testing "docker exec $ANALYTICS_TESTING_CONTAINER psql -U postgres -d postgres -tAc \"
SELECT count(*) FROM analytics_health_log
WHERE checked_at >= TIMESTAMPTZ '${started}'
  AND year = ${YEAR}
  AND check_name IN ('tipo_p_planif_sum','tipo_r_sum','tipo_p_expediente_sum')
  AND company_name IN ($COMPANIES_SQL);
\"" | tr -d '[:space:]')"
    if [[ "${rows}" -ge 6 ]]; then
      echo ""
      ssh_testing "docker exec $ANALYTICS_TESTING_CONTAINER psql -U postgres -d postgres -c \"
SELECT company_name, check_name, bc_value, analytics_value, delta, status
FROM analytics_health_log
WHERE checked_at >= TIMESTAMPTZ '${started}'
  AND year = ${YEAR}
  AND check_name IN ('tipo_p_planif_sum','tipo_r_sum','tipo_p_expediente_sum')
ORDER BY company_name, check_name;
\""
      fails="$(ssh_testing "docker exec $ANALYTICS_TESTING_CONTAINER psql -U postgres -d postgres -tAc \"
SELECT count(*) FROM analytics_health_log
WHERE checked_at >= TIMESTAMPTZ '${started}'
  AND year = ${YEAR}
  AND check_name IN ('tipo_p_planif_sum','tipo_r_sum','tipo_p_expediente_sum')
  AND company_name IN ($COMPANIES_SQL)
  AND status = 'fail';
\"" | tr -d '[:space:]')"
      if [[ "${fails}" != "0" ]]; then
        echo "❌ Gate 021: ${fails} check(s) de dinero en fail (tol 0,50 €)" >&2
        return 1
      fi
      echo "✅ Gate 021: 6/6 checks de dinero ok"
      return 0
    fi
    sleep 15
    elapsed=$((elapsed + 15))
  done
  echo "❌ Timeout 021: solo ${rows:-0}/6 filas de dinero" >&2
  return 1
}

copy_prod_to_testing() {
  echo "📦 Copia Analytics prod → testing (pipe, con backup) ..."
  SSH_PASS="$SSH_PASS" SSH_USER="$SSH_USER" \
    "$APPS_ROOT/scripts/copy-analytics-production-to-env.sh" --target testing --yes --backup
}

confirm_or_die() {
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  echo ""
  echo "Esto va a:"
  [[ "$SKIP_COPY" -eq 0 ]] && echo "  • Sobrescribir Analytics TESTING desde prod"
  echo "  • Aplicar 004/021 en n8n testing y lanzar canary 004 + 021"
  [[ "$APPLY_PROD" -eq 1 ]] && echo "  • Si 021 cierra: aplicar JSON 004 a n8n PROD (sin lanzar 004)"
  read -r -p "¿Confirmas? Escribe yes: " ans
  [[ "$ans" == "yes" ]] || { echo "Cancelado."; exit 0; }
}

# ── main ──────────────────────────────────────────────────────────
[[ -f "$WF_004" ]] || { echo "❌ Falta $WF_004"; exit 1; }
[[ -f "$WF_021" ]] || { echo "❌ Falta $WF_021"; exit 1; }
[[ -x "$APPS_ROOT/scripts/update-n8n-workflow-postgres-remote.sh" ]] || {
  echo "❌ No encuentro update-n8n-workflow-postgres-remote.sh en $APPS_ROOT"; exit 1;
}

echo "════════════════════════════════════════════════════════════"
echo " Gate 004 (testing → prod JSON)"
echo " year=${YEAR} copy=$([[ $SKIP_COPY -eq 1 ]] && echo skip || echo yes) apply_prod=${APPLY_PROD}"
echo "════════════════════════════════════════════════════════════"

confirm_or_die
seatbelt_004

if [[ "$SKIP_COPY" -eq 0 ]]; then
  copy_prod_to_testing
else
  echo "⏭️  --skip-copy: no se refresca el clon testing"
fi

TMPDIR_GATE="$(mktemp -d /tmp/gate-004.XXXXXX)"
trap 'rm -rf "$TMPDIR_GATE"' EXIT
pin_bc_production "$WF_004" "$TMPDIR_GATE/004.testing.json"
pin_bc_production "$WF_021" "$TMPDIR_GATE/021.testing.json"

apply_n8n_postgres "$N8N_TESTING_HOST" "$N8N_TESTING_APP" "$N8N_TESTING_PG" \
  "$WF_004_TESTING" "$TMPDIR_GATE/004.testing.json"
ensure_021_testing "$TMPDIR_GATE/021.testing.json"

echo "🔄 Restart n8n testing (registrar webhooks 004/021) ..."
ssh_testing "docker restart $N8N_TESTING_APP"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf -m 5 "http://${N8N_TESTING_HOST}:5678/healthz" >/dev/null 2>&1 \
     || curl -sf -m 5 "http://${N8N_TESTING_HOST}:5678/" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

reset_testing_watermarks
GATE_004_START="$(date -u +"%Y-%m-%d %H:%M:%S+00:00")"
fire_004_canary psi
wait_004_company psi "$GATE_004_START"
fire_004_canary pslab
wait_004_company pslab "$GATE_004_START"

GATE_021_START="$(date -u +"%Y-%m-%d %H:%M:%S+00:00")"
fire_021
wait_021_money "$GATE_021_START"

if [[ "$APPLY_PROD" -eq 0 ]]; then
  echo ""
  echo "✅ Gate testing OK. --no-prod: no se tocó n8n prod."
  echo "   Para publicar JSON: $0 --yes --skip-copy --apply-prod"
  exit 0
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " HARD STOP prod: aplicar JSON repo a n8n-prod ${WF_004_PROD}"
echo " Impacto: cambia el workflow 004 en VM 101. NO lanza sync."
echo " Rollback: reaplicar el JSON anterior / activeVersionId previo."
echo "════════════════════════════════════════════════════════════"
apply_n8n_postgres "$N8N_PROD_HOST" "$N8N_PROD_APP" "$N8N_PROD_PG" \
  "$WF_004_PROD" "$WF_004"

echo ""
echo "✅ Gate completo."
echo "   Testing: 004+021 aplicados, canary ${YEAR} ok, 021 dinero ok"
echo "   Prod:    JSON 004 aplicado. NO se lanzó 004 en prod."
echo "   Si hace falta resync prod: webhook sync-bc-to-analytics a mano."
