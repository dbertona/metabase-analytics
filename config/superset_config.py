"""Configuración Apache Superset - PS Analytics."""

import os

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "PsSupersetSecretKey2026ChangeMe")

# Flags útiles en 6.x (algunas nativas ya vienen on por defecto)
FEATURE_FLAGS = {
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}

WTF_CSRF_ENABLED = True

# Publicación bajo https://apps.powersolution.es/analytics/
# (Nginx Proxy Manager → VM 100:8088; SUPERSET_APP_ROOT en compose)
_app_root = (os.environ.get("SUPERSET_APP_ROOT") or "").rstrip("/") or None
if _app_root:
    APPLICATION_ROOT = _app_root
    STATIC_ASSETS_PREFIX = _app_root

ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {"x_for": 1, "x_proto": 1, "x_host": 1, "x_port": 1, "x_prefix": 1}
