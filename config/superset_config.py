"""Configuración Apache Superset - PS Analytics."""

from __future__ import annotations

import logging
import os
from typing import Any

import jwt
import psycopg2
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
# El montaje real lo hace AppRootMiddleware vía create_app(superset_app_root=...).
#
# Workaround bug BETA APP_ROOT (Superset 6.1): create_app antepone el prefijo a
# brandLogoUrl / APP_ICON, y el frontend vuelve a anteponer
# static_assets_prefix / application_root → /analytics/analytics/... (404).
# - STATIC_ASSETS_PREFIX="/" es truthy (create_app no lo pisa) y el JS lo
#   normaliza quitando la barra final → prefijo vacío.
# - APPLICATION_ROOT="" evita que create_app lo sustituya por /analytics y que
#   el JS duplique hrefs ya prefijados en el bootstrap.
STATIC_ASSETS_PREFIX = "/"
APPLICATION_ROOT = ""

ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {"x_for": 1, "x_proto": 1, "x_host": 1, "x_port": 1, "x_prefix": 1}
PREFERRED_URL_SCHEME = "https"

# Sesión detrás de NPM + /analytics/: evita
# "mismatching_state: CSRF Warning! State not equal" en OAuth Azure
# (si Path=/analytics a veces se pierde el state al volver de Microsoft).
SESSION_COOKIE_NAME = "superset_session"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_SAMESITE = "Lax"
SESSION_COOKIE_PATH = "/"
REMEMBER_COOKIE_SECURE = True
REMEMBER_COOKIE_PATH = "/"

# Analytics DB (misma red Docker: supabase-db) — lookup bc_resource
PS_ANALYTICS_HOST = os.environ.get("PS_ANALYTICS_HOST", "supabase-db").strip()
PS_ANALYTICS_PORT = int(os.environ.get("PS_ANALYTICS_PORT", "5432"))
PS_ANALYTICS_DB = os.environ.get("PS_ANALYTICS_DB", "postgres").strip()
PS_ANALYTICS_USER = os.environ.get("PS_ANALYTICS_USER", "postgres").strip()
PS_ANALYTICS_PASSWORD = os.environ.get(
    "PS_ANALYTICS_PASSWORD", "SuperSecurePassword2025"
).strip()


def lookup_resource_name(email: str) -> str | None:
    """Nombre completo en bc_resource por email (como Timesheet)."""
    email = (email or "").strip().lower()
    if not email or "@" not in email:
        return None
    try:
        with psycopg2.connect(
            host=PS_ANALYTICS_HOST,
            port=PS_ANALYTICS_PORT,
            dbname=PS_ANALYTICS_DB,
            user=PS_ANALYTICS_USER,
            password=PS_ANALYTICS_PASSWORD,
            connect_timeout=5,
        ) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT name
                    FROM public.bc_resource
                    WHERE lower(trim(email)) = %s
                      AND coalesce(trim(name), '') <> ''
                    ORDER BY company_name
                    LIMIT 1
                    """,
                    (email,),
                )
                row = cur.fetchone()
                if row and row[0]:
                    return str(row[0]).strip()
    except Exception:
        logger.exception("No se pudo leer bc_resource para email=%s", email)
    return None


def split_resource_display_name(full_name: str, email: str) -> tuple[str, str]:
    """Convierte 'Apellido, Nombre' (BC) → (Nombre, Apellido) para la barra."""
    full_name = (full_name or "").strip()
    if not full_name:
        local = email.split("@")[0] if email else "usuario"
        return local, ""
    if "," in full_name:
        last, first = full_name.split(",", 1)
        first, last = first.strip(), last.strip()
        if first:
            return first, last
    parts = full_name.split(None, 1)
    if len(parts) == 2:
        return parts[0], parts[1]
    return full_name, ""


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
        """Azure SSO + nombre desde bc_resource (igual que Timesheet)."""

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

            resource_name = lookup_resource_name(email)
            if resource_name:
                first_name, last_name = split_resource_display_name(resource_name, email)
                logger.info(
                    "Azure OAuth: %s → bc_resource.name=%r → %s %s",
                    email,
                    resource_name,
                    first_name,
                    last_name,
                )
            else:
                first_name = me.get("given_name") or email.split("@")[0]
                last_name = me.get("family_name") or ""
                logger.info(
                    "Azure OAuth: %s sin match en bc_resource; usando claims Azure",
                    email,
                )

            return {
                "username": email,
                "email": email,
                "first_name": first_name,
                "last_name": last_name,
            }

        def oauth_user_info(self, provider: str, response: dict[str, Any] | None = None):
            return self.get_oauth_user_info(provider, response)

        def auth_user_oauth(self, userinfo: dict[str, Any]):
            """Crea o actualiza first/last name en cada login (barra superior)."""
            user = super().auth_user_oauth(userinfo)
            if not user or not userinfo:
                return user
            first_name = (userinfo.get("first_name") or "").strip()
            last_name = (userinfo.get("last_name") or "").strip()
            if not first_name and not last_name:
                return user
            if user.first_name == first_name and user.last_name == last_name:
                return user
            try:
                user.first_name = first_name or user.first_name
                user.last_name = last_name
                self.update_user(user)
                logger.info(
                    "Usuario actualizado: %s → %s %s",
                    user.username,
                    user.first_name,
                    user.last_name,
                )
            except Exception:
                logger.exception("No se pudo actualizar nombre de %s", user.username)
            return user

    CUSTOM_SECURITY_MANAGER = AzureSsoSecurityManager
else:
    # Sin secret → login local (admin) para DEV / recuperación
    AUTH_TYPE = AUTH_DB
