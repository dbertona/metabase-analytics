#!/bin/bash
# OBSOLETO — El n8n en VM 100 (Analytics) fue retirado el 2026-07-07.
#
# El workflow 004 se gestiona desde n8n PRODUCCIÓN (VM 101):
#   https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e
#
# Para actualizar el JSON en n8n prod desde este repo:
#   ./scripts/update-n8n-workflow-004-api.sh
#
# Ver: docs/ACTUALIZAR_WORKFLOW_004.md

set -e

echo "❌ Este script ya no aplica: no hay n8n en VM 100 (Analytics)."
echo ""
echo "✅ Workflow 004 — producción:"
echo "   UI:  https://apps.powersolution.es/n8n/workflow/d1f7647e114a486e"
echo "   Sync: POST https://apps.powersolution.es/n8n/webhook/sync-bc-to-analytics?company=psi"
echo ""
echo "✅ Actualizar JSON:"
echo "   ./scripts/update-n8n-workflow-004-api.sh"
echo ""
echo "📖 docs/ACTUALIZAR_WORKFLOW_004.md"
exit 1
