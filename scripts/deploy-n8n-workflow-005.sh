#!/bin/bash
# Crea o actualiza el workflow 005 (Health Check Analytics vs BC) en n8n prod (VM 101).
# Usa PostgreSQL de n8n (mismo método que 004).
#
# Uso: ./scripts/deploy-n8n-workflow-005.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF_FILE="$ROOT/src/workflows/005_health_check_analytics_bc.json"
WF_ID="e005a1b2c3d4e5f6"
HOST="${N8N_HOST:-192.168.36.101}"
USER="${N8N_SSH_USER:-ps_admin}"
PASS="${N8N_SSH_PASS:-PsAdmin2025}"
N8N_DB_PASSWORD="${N8N_DB_PASSWORD:-c7DxE3KNX72LlRzYPf5KGDskeM84jWvn}"
PROJECT_ID="${N8N_PROJECT_ID:-HvpEZJBQb1R4siPC}"

if [[ ! -f "$WF_FILE" ]]; then
  echo "❌ No existe $WF_FILE"
  exit 1
fi

python3 -m json.tool "$WF_FILE" >/dev/null
echo "✅ JSON válido"

sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
  "$WF_FILE" \
  "$USER@$HOST:/tmp/005_health_check_analytics_bc.json"

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$HOST" bash <<REMOTE
set -euo pipefail
export N8N_DB_PASSWORD='$N8N_DB_PASSWORD'
python3 <<'PY'
import json, os, subprocess, uuid
from datetime import datetime, timezone

WF_ID = "$WF_ID"
PROJECT_ID = "$PROJECT_ID"
PG_PASSWORD = os.environ["N8N_DB_PASSWORD"]
path = "/tmp/005_health_check_analytics_bc.json"

def psql(sql: str, input_sql: str | None = None) -> str:
    cmd = [
        "docker", "exec", "-i",
        "-e", f"PGPASSWORD={PG_PASSWORD}",
        "supabase-db", "psql", "-h", "localhost", "-U", "n8n", "-d", "n8n",
        "-v", "ON_ERROR_STOP=1",
    ]
    if input_sql is None:
        cmd.extend(["-tAc", sql])
        proc = subprocess.run(cmd, capture_output=True, text=True)
    else:
        proc = subprocess.run(cmd, input=input_sql, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(proc.stderr or proc.stdout)
    return (proc.stdout or "").strip()

def sql_json(v):
    return json.dumps(v, ensure_ascii=False).replace("'", "''")

data = json.loads(open(path, encoding="utf-8").read())
wf = data[0] if isinstance(data, list) else data
nodes = wf.get("nodes", [])
connections = wf.get("connections", {})
settings = wf.get("settings") or {}
name = wf.get("name") or "005 - Health Check Analytics vs BC"
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
hist_now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
new_version = str(uuid.uuid4())

exists = psql(f"SELECT id FROM workflow_entity WHERE id = '{WF_ID}'")
if exists:
    print(f"Updating existing workflow {WF_ID}")
    sql = f"""
BEGIN;
INSERT INTO workflow_history (
  "versionId", "workflowId", authors, "createdAt", "updatedAt",
  nodes, connections, name, autosaved, description, "nodeGroups"
) VALUES (
  '{new_version}', '{WF_ID}', 'deploy-n8n-workflow-005.sh',
  '{hist_now}', '{hist_now}',
  '{sql_json(nodes)}'::json, '{sql_json(connections)}'::json,
  'Version {new_version[:8]}', false, NULL, '[]'::json
);
UPDATE workflow_entity SET
  name = '{name.replace("'", "''")}',
  nodes = '{sql_json(nodes)}'::json,
  connections = '{sql_json(connections)}'::json,
  settings = '{sql_json(settings)}'::json,
  "updatedAt" = '{now}',
  "activeVersionId" = '{new_version}',
  "versionId" = '{new_version}',
  active = true
WHERE id = '{WF_ID}';
COMMIT;
"""
    psql("", sql)
else:
    print(f"Creating workflow {WF_ID}")
    # Insert history first requires workflow row; use deferred activeVersion
    sql = f"""
BEGIN;
INSERT INTO workflow_entity (
  id, name, active, nodes, connections, "createdAt", "updatedAt",
  settings, "staticData", "pinData", "versionId", "triggerCount",
  meta, "isArchived", "versionCounter", "nodeGroups"
) VALUES (
  '{WF_ID}',
  '{name.replace("'", "''")}',
  false,
  '{sql_json(nodes)}'::json,
  '{sql_json(connections)}'::json,
  '{now}', '{now}',
  '{sql_json(settings)}'::json,
  NULL, NULL,
  '{new_version}',
  1,
  '{{"templateCredsSetupCompleted": true}}'::json,
  false,
  1,
  '[]'::json
);
INSERT INTO workflow_history (
  "versionId", "workflowId", authors, "createdAt", "updatedAt",
  nodes, connections, name, autosaved, description, "nodeGroups"
) VALUES (
  '{new_version}', '{WF_ID}', 'deploy-n8n-workflow-005.sh',
  '{hist_now}', '{hist_now}',
  '{sql_json(nodes)}'::json, '{sql_json(connections)}'::json,
  'Version {new_version[:8]}', false, NULL, '[]'::json
);
UPDATE workflow_entity SET
  "activeVersionId" = '{new_version}',
  active = true,
  "updatedAt" = '{now}'
WHERE id = '{WF_ID}';
INSERT INTO shared_workflow ("workflowId", "projectId", role, "createdAt", "updatedAt")
VALUES ('{WF_ID}', '{PROJECT_ID}', 'workflow:owner', '{hist_now}', '{hist_now}')
ON CONFLICT ("workflowId", "projectId") DO NOTHING;
COMMIT;
"""
    psql("", sql)

n = psql(f"SELECT json_array_length(nodes::json), active FROM workflow_entity WHERE id='{WF_ID}'")
print(f"OK {name}: {n}")
PY
REMOTE

echo ""
echo "✅ Workflow 005 desplegado en n8n prod"
echo "   UI: https://apps.powersolution.es/n8n/workflow/${WF_ID}"
echo "   Manual: POST https://apps.powersolution.es/n8n/webhook/analytics-health-check"
echo "   Schedule: L-V 07:00 Europe/Madrid"
