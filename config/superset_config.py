"""Configuración Apache Superset - PS Analytics."""

from __future__ import annotations

import logging
import os
from typing import Any

import jwt
import psycopg2
from flask_appbuilder.security.manager import AUTH_DB, AUTH_OAUTH
from flask import Flask
from superset.initialization import SupersetAppInitializer
from superset.security import SupersetSecurityManager

logger = logging.getLogger(__name__)

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "PsSupersetSecretKey2026ChangeMe")

# Flags útiles en 6.x (algunas nativas ya vienen on por defecto)
FEATURE_FLAGS = {
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    # Table V2 (AG Grid): resize de columnas con el ratón, pin, autosize, etc.
    "AG_GRID_TABLE_ENABLED": True,
}

WTF_CSRF_ENABLED = True

# Interfaz en español (pack montado en docker-compose; imagen lean no lo trae)
BABEL_DEFAULT_LOCALE = "es"
BABEL_DEFAULT_FOLDER = "superset/translations"
LANGUAGES = {
    "es": {"flag": "es", "name": "Español"},
    "en": {"flag": "us", "name": "English"},
}


def COMMON_BOOTSTRAP_OVERRIDES_FUNC(bootstrap_data: dict[str, Any]) -> dict[str, Any]:
    """Inyecta language_pack ES en el bootstrap (Superset 6 solo lo sirve con login)."""
    from flask_babel import get_locale
    from superset.translations.utils import get_language_pack

    locale = bootstrap_data.get("locale") or str(get_locale() or "es")
    if hasattr(locale, "language"):
        locale = locale.language  # type: ignore[assignment]
    locale = str(locale or "es")
    pack = get_language_pack(locale) or get_language_pack("es")
    return {"language_pack": pack or {}}

# Publicación bajo https://apps.powersolution.es/analytics/
# create_app(superset_app_root=...) monta AppRootMiddleware y fija
# APPLICATION_ROOT / STATIC_ASSETS_PREFIX = /analytics.
#
# Bug BETA APP_ROOT (Superset 6.1): create_app también antepone /analytics a
# brandLogoUrl / APP_ICON, pero el frontend vuelve a anteponer
# static_assets_prefix → /analytics/analytics/... (404) o, si se fuerza
# STATIC_ASSETS_PREFIX="/", el HTML genera //static/... (host inventado).
# Mismo bug en menú Logout: bootstrap ya trae user_logout_url=/analytics/logout/
# y ensureAppRoot() antepone otra vez → /analytics/analytics/logout/ (404).
# Solución: deshacer doble prefijo del theme + middleware que colapsa
# /analytics/analytics/* → /analytics/*.


class _CollapseDoubleAppRootMiddleware:
    """Colapsa PATH_INFO con APP_ROOT duplicado (logout/menu/links)."""

    def __init__(self, wsgi_app: Any, app_root: str) -> None:
        self.wsgi_app = wsgi_app
        self.app_root = (app_root or "").rstrip("/")
        self.double = f"{self.app_root}{self.app_root}" if self.app_root else ""

    def __call__(self, environ: dict[str, Any], start_response: Any) -> Any:
        if self.double:
            path = environ.get("PATH_INFO") or ""
            if path == self.double or path.startswith(f"{self.double}/"):
                environ = dict(environ)
                environ["PATH_INFO"] = path[len(self.app_root) :] or "/"
        return self.wsgi_app(environ, start_response)


class PsAppInitializer(SupersetAppInitializer):
    """Corrige URLs de theme duplicadas y doble APP_ROOT en rutas."""

    def __init__(self, app: Flask) -> None:
        super().__init__(app)
        self._unprefix_app_root_theme_urls()

    def _app_root(self) -> str:
        return (
            os.environ.get("SUPERSET_APP_ROOT")
            or self.superset_app.config.get("APPLICATION_ROOT")
            or ""
        ).rstrip("/")

    def _unprefix_app_root_theme_urls(self) -> None:
        app_root = self._app_root()
        if not app_root or app_root == "/":
            return

        def strip_root(path: str) -> str:
            if path.startswith(f"{app_root}/"):
                return path[len(app_root) :]
            if path == app_root:
                return "/"
            return path

        icon = self.superset_app.config.get("APP_ICON") or ""
        if icon.startswith(f"{app_root}/static/"):
            self.superset_app.config["APP_ICON"] = strip_root(icon)

        for theme_key in ("THEME_DEFAULT", "THEME_DARK"):
            theme = self.superset_app.config.get(theme_key) or {}
            token = theme.get("token") or {}
            url = token.get("brandLogoUrl") or ""
            if url.startswith(f"{app_root}/static/"):
                token["brandLogoUrl"] = strip_root(url)
            href = token.get("brandLogoHref") or ""
            if href == app_root or href == f"{app_root}/":
                token["brandLogoHref"] = "/"

    def post_init(self) -> None:
        super().post_init()
        app = self.superset_app
        app_root = self._app_root()
        if app_root and app_root != "/":
            app.wsgi_app = _CollapseDoubleAppRootMiddleware(app.wsgi_app, app_root)
            logger.info(
                "PS: middleware anti doble APP_ROOT activo (%s%s → %s)",
                app_root,
                app_root,
                app_root,
            )

        # Forzar locale español en sesión (usuarios con cookie en "en")
        from flask import session

        @app.before_request
        def _ps_force_locale_es() -> None:
            if session.get("locale") != "es":
                session["locale"] = "es"

        self._register_ps_simulation_routes()
        self._ensure_ps_testing_role()

    def _ensure_ps_testing_role(self) -> None:
        """Crea el rol PS_Testing si no existe (flag para combo simulación)."""
        try:
            app = self.superset_app
            with app.app_context():
                sm = app.appbuilder.sm
                if sm.find_role("PS_Testing"):
                    return
                sm.add_role("PS_Testing")
                logger.info("PS: rol PS_Testing creado (simulación de usuario)")
        except Exception:
            logger.exception("PS: no se pudo crear el rol PS_Testing")

    def _register_ps_simulation_routes(self) -> None:
        """APIs PS: simulación (Admin/Alpha/PS_Testing) + ámbito departamento (todos)."""
        from flask import jsonify, request, session

        app = self.superset_app

        @app.get("/api/v1/ps/resources")
        def ps_list_resources_for_simulation():  # type: ignore[no-untyped-def]
            # JSON 401 (no @login_required): evita BuildError del redirect a 'login'
            user = _ps_resolve_request_user()
            if not user:
                return jsonify({"message": "Unauthorized", "can_simulate": False}), 401
            if not _ps_can_simulate(user):
                return jsonify({"message": "Forbidden", "can_simulate": False}), 403
            resources = list_resources_for_simulation()
            return jsonify(
                {
                    "result": resources,
                    "count": len(resources),
                    "can_simulate": True,
                }
            )

        @app.get("/api/v1/ps/user-scope")
        def ps_user_department_scope():  # type: ignore[no-untyped-def]
            """Ámbito de departamento (paridad PBI: vacío/999 = ver todo)."""
            user = _ps_resolve_request_user()
            if not user:
                return jsonify({"message": "Unauthorized"}), 401

            real_email = _ps_user_email(user)
            requested = (request.args.get("email") or "").strip().lower()
            effective = requested or real_email
            if not effective or "@" not in effective:
                return jsonify({"message": "Email inválido"}), 400

            # Simular otro email solo con rol de simulación
            if requested and requested != real_email and not _ps_can_simulate(user):
                return jsonify({"message": "Forbidden", "can_simulate": False}), 403

            scope = resolve_department_scope(effective)
            scope["real_email"] = real_email
            scope["simulated"] = bool(requested and requested != real_email)
            return jsonify({"result": scope})

        @app.post("/api/v1/ps/simulate")
        def ps_set_simulation():  # type: ignore[no-untyped-def]
            """Guarda email simulado en session Flask (RLS Jinja lo lee)."""
            user = _ps_resolve_request_user()
            if not user:
                return jsonify({"message": "Unauthorized"}), 401
            if not _ps_can_simulate(user):
                return jsonify({"message": "Forbidden"}), 403
            body = request.get_json(silent=True) or {}
            email = (body.get("email") or "").strip().lower()
            if not email:
                session.pop(PS_SIMULATED_EMAIL_SESSION_KEY, None)
                return jsonify({"result": {"simulated": False, "email": None}})
            if "@" not in email:
                return jsonify({"message": "Email inválido"}), 400
            session[PS_SIMULATED_EMAIL_SESSION_KEY] = email
            scope = resolve_department_scope(email)
            return jsonify(
                {
                    "result": {
                        "simulated": True,
                        "email": email,
                        "see_all": scope["see_all"],
                        "department_code": scope["department_code"],
                    }
                }
            )

        @app.delete("/api/v1/ps/simulate")
        def ps_clear_simulation():  # type: ignore[no-untyped-def]
            user = _ps_resolve_request_user()
            if not user:
                return jsonify({"message": "Unauthorized"}), 401
            session.pop(PS_SIMULATED_EMAIL_SESSION_KEY, None)
            return jsonify({"result": {"simulated": False, "email": None}})

        logger.info(
            "PS: rutas /api/v1/ps/resources + /user-scope + /simulate (%s)",
            ",".join(sorted(PS_SIMULATION_ROLES)),
        )

APP_INITIALIZER = PsAppInitializer

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

# Roles que pueden usar el combo de simulación (identidad + ámbito departamento).
PS_SIMULATION_ROLES = frozenset({"Admin", "Alpha", "PS_Testing"})

# Analytics DB (misma red Docker: supabase-db) — lookup bc_resource
PS_ANALYTICS_HOST = os.environ.get("PS_ANALYTICS_HOST", "supabase-db").strip()
PS_ANALYTICS_PORT = int(os.environ.get("PS_ANALYTICS_PORT", "5432"))
PS_ANALYTICS_DB = os.environ.get("PS_ANALYTICS_DB", "postgres").strip()
PS_ANALYTICS_USER = os.environ.get("PS_ANALYTICS_USER", "postgres").strip()
PS_ANALYTICS_PASSWORD = os.environ.get(
    "PS_ANALYTICS_PASSWORD", "SuperSecurePassword2025"
).strip()


def _analytics_connect():
    """Conexión corta a Analytics DB (bc_resource)."""
    return psycopg2.connect(
        host=PS_ANALYTICS_HOST,
        port=PS_ANALYTICS_PORT,
        dbname=PS_ANALYTICS_DB,
        user=PS_ANALYTICS_USER,
        password=PS_ANALYTICS_PASSWORD,
        connect_timeout=5,
    )


def lookup_resource_name(email: str) -> str | None:
    """Nombre completo en bc_resource por email (como Timesheet)."""
    email = (email or "").strip().lower()
    if not email or "@" not in email:
        return None
    try:
        with _analytics_connect() as conn:
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


def list_resources_for_simulation() -> list[dict[str, str]]:
    """Recursos activos con email (misma lógica que UserSimulatorSelector en Apps)."""
    try:
        with _analytics_connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT code, name, email
                    FROM public.bc_resource
                    WHERE email IS NOT NULL
                      AND trim(email) <> ''
                      AND fecha_de_baja IS NULL
                      AND code NOT LIKE %s
                    ORDER BY name NULLS LAST, email
                    """,
                    ("REC.%",),
                )
                rows = cur.fetchall()
    except Exception:
        logger.exception("No se pudo listar bc_resource para simulación")
        return []

    seen: set[str] = set()
    out: list[dict[str, str]] = []
    for code, name, email in rows:
        email_n = (email or "").strip().lower()
        if not email_n or email_n in seen:
            continue
        seen.add(email_n)
        out.append(
            {
                "code": str(code or "").strip(),
                "name": str(name or "").strip() or email_n,
                "email": email_n,
            }
        )
    return out


def lookup_user_departamento(email: str) -> str:
    """Departamento en bc_user_configuration por email (preferir valor no vacío)."""
    email = (email or "").strip().lower()
    if not email or "@" not in email:
        return ""
    try:
        with _analytics_connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT trim(departamento)
                    FROM public.bc_user_configuration
                    WHERE lower(trim(email)) = %s
                      AND coalesce(trim(departamento), '') <> ''
                    ORDER BY company_name
                    LIMIT 1
                    """,
                    (email,),
                )
                row = cur.fetchone()
                if row and row[0]:
                    return str(row[0]).strip()
    except Exception:
        logger.exception(
            "No se pudo leer bc_user_configuration.departamento para email=%s", email
        )
    return ""


def resolve_department_scope(email: str) -> dict[str, Any]:
    """Paridad PBI: vacío o '999' → ver todos los departamentos."""
    email_n = (email or "").strip().lower()
    dept = lookup_user_departamento(email_n)
    see_all = dept == "" or dept == "999"
    return {
        "email": email_n,
        "departamento": dept or None,
        "see_all": see_all,
        "department_code": None if see_all else dept,
    }


PS_SIMULATED_EMAIL_SESSION_KEY = "ps_simulated_email"


def _ps_resolve_request_user() -> Any:
    """Usuario autenticado: cookie Flask-Login, g.user o JWT Bearer."""
    try:
        from flask import current_app, g, request
        from flask_login import current_user

        if current_user and getattr(current_user, "is_authenticated", False):
            return current_user
        gu = getattr(g, "user", None)
        if gu and getattr(gu, "is_authenticated", False):
            return gu
        auth = request.headers.get("Authorization") or ""
        if not auth.startswith("Bearer "):
            return None
        from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request

        verify_jwt_in_request(optional=False)
        identity = get_jwt_identity()
        if identity is None:
            return None
        user = current_app.appbuilder.sm.load_user(identity)
        if user and getattr(user, "is_active", True):
            g.user = user
            return user
    except Exception:
        logger.debug("PS: no se pudo resolver usuario de request", exc_info=True)
    return None


def _ps_user_email(user: Any) -> str:
    return (
        (getattr(user, "email", None) or getattr(user, "username", None) or "")
        .strip()
        .lower()
    )


def _ps_can_simulate(user: Any) -> bool:
    if not user:
        return False
    roles = {getattr(r, "name", "") for r in (getattr(user, "roles", None) or [])}
    return bool(roles & PS_SIMULATION_ROLES)


def _ps_effective_email_for_rls() -> str:
    """Email efectivo para RLS: simulación en session (si autorizada) o usuario real."""
    from flask import session

    user = _ps_resolve_request_user()
    if not user:
        return ""
    real = _ps_user_email(user)
    sim = (session.get(PS_SIMULATED_EMAIL_SESSION_KEY) or "").strip().lower()
    if sim and sim != real and _ps_can_simulate(user):
        return sim
    return real


def _ps_dept_jinja_filter() -> str:
    """Cláusula SQL WHERE para RLS de departamento.

    - Departamento vacío/999 del email efectivo → 1=1
    - Email efectivo con departamento → department_code = 'DEPT'
    - Sin usuario → 1=0

    La simulación Admin → otro email se guarda en session Flask
    (POST /api/v1/ps/simulate). Sin eso, Admin siempre veía todo aunque
    el filtro nativo estuviera aplicado (y podía borrarlo).

    Registrada como función Jinja en JINJA_CONTEXT_ADDONS.
    """
    try:
        email = _ps_effective_email_for_rls()
        if not email or "@" not in email:
            return "1=0"
        scope = resolve_department_scope(email)
        if scope["see_all"]:
            return "1=1"
        dept = (scope.get("department_code") or "").strip()
        if not dept:
            return "1=0"
        dept_safe = dept.replace("'", "''")
        return f"department_code = '{dept_safe}'"
    except Exception:
        logger.exception("ps_dept_filter: error determinando ámbito de departamento")
        return "1=0"


# Función Jinja disponible en todos los datasets con ENABLE_TEMPLATE_PROCESSING=True.
# Uso en virtual SQL: SELECT * FROM bi_v_xxx WHERE {{ ps_dept_filter() }}
JINJA_CONTEXT_ADDONS = {
    "ps_dept_filter": _ps_dept_jinja_filter,
}


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
    # Solo lectura (sin Edit chart). Admin/Alpha se asignan a mano.
    # Rol custom PS_Viewer en metadata DB (sin can_explore / can_write Chart).
    AUTH_USER_REGISTRATION_ROLE = "PS_Viewer"
    AUTH_ROLES_SYNC_AT_LOGIN = False

    OAUTH_PROVIDERS = [
        {
            "name": "azure",
            "icon": "fa-windows",
            "token_key": "access_token",
            "remote_app": {
                "client_id": AZURE_CLIENT_ID,
                "client_secret": AZURE_CLIENT_SECRET,
                # Fijo: si url_for pierde SCRIPT_NAME, Azure redirige a
                # /oauth-authorized/azure → nginx lo manda a Timesheet (AppError 404).
                "redirect_uri": (
                    "https://apps.powersolution.es/analytics/oauth-authorized/azure"
                ),
                "server_metadata_url": (
                    # Debe ser /v2.0/... : el metadata v1 expone iss
                    # sts.windows.net y el id_token v2.0 usa
                    # login.microsoftonline.com/.../v2.0 → invalid_claim 'iss'
                    f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
                    "/v2.0/.well-known/openid-configuration"
                ),
                "client_kwargs": {
                    "scope": "openid email profile User.Read offline_access",
                    "token_endpoint_auth_method": "client_secret_post",
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
