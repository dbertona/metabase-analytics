"""Configuración Apache Superset - PS Analytics."""

from __future__ import annotations

import logging
import os
from typing import Any

import jwt
from flask_appbuilder.security.manager import AUTH_DB, AUTH_OAUTH
from superset.security import SupersetSecurityManager

logger = logging.getLogger(__name__)

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "PsSupersetSecretKey2026ChangeMe")

# Flags útiles en 6.x (algunas nativas ya vienen on por defecto)
FEATURE_FLAGS = {
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}

WTF_CSRF_ENABLED = True

# Publicación bajo https://apps.powersolution.es/analytics/
_app_root = (os.environ.get("SUPERSET_APP_ROOT") or "").rstrip("/") or None
if _app_root:
    APPLICATION_ROOT = _app_root
    STATIC_ASSETS_PREFIX = _app_root

ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {"x_for": 1, "x_proto": 1, "x_host": 1, "x_port": 1, "x_prefix": 1}
PREFERRED_URL_SCHEME = "https"

# ── Azure AD / Entra ID (misma App Registration que Timesheet) ─────────────
# Redirect URI (plataforma Web en Azure):
#   https://apps.powersolution.es/analytics/oauth-authorized/azure
AZURE_TENANT_ID = os.environ.get(
    "AZURE_TENANT_ID", "a18dc497-a8b8-4740-b723-65362ab7a3fb"
).strip()
AZURE_CLIENT_ID = os.environ.get(
    "AZURE_CLIENT_ID", "3975625e-617d-410c-a166-9a3c88563344"
).strip()
AZURE_CLIENT_SECRET = os.environ.get("AZURE_CLIENT_SECRET", "").strip()

if AZURE_CLIENT_SECRET:
    AUTH_TYPE = AUTH_OAUTH
    AUTH_USER_REGISTRATION = True
    # Solo lectura por defecto; Admin se asigna a mano en Settings → Users
    AUTH_USER_REGISTRATION_ROLE = "Gamma"
    AUTH_ROLES_SYNC_AT_LOGIN = False

    OAUTH_PROVIDERS = [
        {
            "name": "azure",
            "icon": "fa-windows",
            "token_key": "access_token",
            "remote_app": {
                "client_id": AZURE_CLIENT_ID,
                "client_secret": AZURE_CLIENT_SECRET,
                "server_metadata_url": (
                    f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
                    "/.well-known/openid-configuration"
                ),
                "client_kwargs": {
                    "scope": "openid email profile User.Read offline_access",
                },
                "api_base_url": "https://graph.microsoft.com/v1.0/",
                "request_token_url": None,
                "access_token_url": (
                    f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
                    "/oauth2/v2.0/token"
                ),
                "authorize_url": (
                    f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
                    "/oauth2/v2.0/authorize"
                ),
                "jwks_uri": (
                    f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
                    "/discovery/v2.0/keys"
                ),
            },
        }
    ]

    class AzureSsoSecurityManager(SupersetSecurityManager):
        """Mapea claims de Azure (UPN/email) a usuario Superset."""

        def get_oauth_user_info(
            self, provider: str, response: dict[str, Any] | None = None
        ) -> dict[str, Any]:
            if provider != "azure":
                return super().get_oauth_user_info(provider, response)

            response = response or {}
            id_token = response.get("id_token")
            if not id_token:
                logger.error("Azure OAuth: respuesta sin id_token")
                return {}

            # Claims del id_token (firma ya validada por Authlib/OIDC en el flujo)
            me = jwt.decode(
                id_token,
                options={"verify_signature": False},
                algorithms=["RS256", "RS384", "RS512"],
            )
            email = (
                me.get("preferred_username")
                or me.get("email")
                or me.get("upn")
                or me.get("unique_name")
                or ""
            )
            email = str(email).strip().lower()
            if not email:
                logger.error("Azure OAuth: sin email/UPN en id_token keys=%s", list(me))
                return {}

            info = {
                "username": email,
                "email": email,
                "first_name": me.get("given_name") or email.split("@")[0],
                "last_name": me.get("family_name") or "",
            }
            logger.info("Azure OAuth login: %s", email)
            return info

        # Compat FAB versiones que llaman oauth_user_info
        def oauth_user_info(self, provider: str, response: dict[str, Any] | None = None):
            return self.get_oauth_user_info(provider, response)

    CUSTOM_SECURITY_MANAGER = AzureSsoSecurityManager
else:
    # Sin secret → login local (admin) para DEV / recuperación
    AUTH_TYPE = AUTH_DB
