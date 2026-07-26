#!/usr/bin/env python3
"""Configura Superset con capa BI mantenible (mismos datos que Power BI).

Flujo:
  1. Aplica vistas SQL bi_v_* en PostgreSQL
  2. Crea datasets físicos (sin SQL embebido en Python)
  3. Crea tarjetas KPI + tablas + gráficos
  4. Persiste filtros nativos (valores desde bi_v_evolucion_mensual)

Ver: docs/FILTROS_DASHBOARD_PLANIFICACION.md
"""

from __future__ import annotations

import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SUPERSET_URL = os.environ.get("SUPERSET_URL", "http://localhost:8088/analytics").rstrip("/")
SUPERSET_USER = os.environ.get("SUPERSET_USER", "admin")
SUPERSET_PASSWORD = os.environ.get("SUPERSET_PASSWORD", "PsSuperset#2026xK9!")
CURRENT_YEAR = datetime.date.today().year
DEFAULT_EMPRESA = "Power Solution Iberia SL"  # paridad panel Resumen PBI (PSI)
DASHBOARD_TITLE = "Seguimiento Económico — Resumen"
DASHBOARD_SLUG = "planificacion-ps-analytics"  # URL estable (Fase 3)

PS_DB = {
    "database_name": "PS Analytics",
    "sqlalchemy_uri": (
        "postgresql+psycopg2://postgres:SuperSecurePassword2025"
        "@supabase-db:5432/postgres"
    ),
    "expose_in_sqllab": True,
    "allow_run_async": True,
    "extra": json.dumps({"schemas_allowed_for_file_upload": []}),
}

DATASETS = [
    "bi_v_kpi_anual_empresa",
    "bi_v_planificacion_kpi",
    "bi_v_evolucion_mensual",
    "bi_v_facturacion_probabilidad",
    "bi_v_resumen_proyectos",
]


class SupersetClient:
    def __init__(self) -> None:
        self.token: str | None = None
        self.csrf: str | None = None
        self.jar = CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar)
        )

    def _request(
        self, method: str, path: str, payload: dict[str, Any] | None = None, *, auth: bool = True
    ) -> Any:
        headers = {"Content-Type": "application/json"}
        if auth and self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if auth and self.csrf:
            headers["X-CSRFToken"] = self.csrf
            headers["Referer"] = SUPERSET_URL + "/"
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(
            f"{SUPERSET_URL}{path}", data=data, method=method, headers=headers
        )
        try:
            with self.opener.open(req, timeout=90) as resp:
                body = resp.read().decode()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"{method} {path} -> {exc.code}: {exc.read().decode()}") from exc

    def login(self) -> None:
        res = self._request(
            "POST",
            "/api/v1/security/login",
            {
                "username": SUPERSET_USER,
                "password": SUPERSET_PASSWORD,
                "provider": "db",
                "refresh": True,
            },
            auth=False,
        )
        self.token = res["access_token"]
        self.csrf = self._request("GET", "/api/v1/security/csrf_token/")["result"]

    def ensure_database(self) -> int:
        q = {"filters": [{"col": "database_name", "opr": "eq", "value": PS_DB["database_name"]}]}
        res = self._request("GET", f"/api/v1/database/?q={urllib.parse.quote(json.dumps(q))}")
        items = res.get("result") or []
        if items:
            db_id = items[0]["id"]
            self._request("PUT", f"/api/v1/database/{db_id}", PS_DB)
            print(f"BD actualizada: {PS_DB['database_name']} (id={db_id})")
            return db_id
        db_id = self._request("POST", "/api/v1/database/", PS_DB)["id"]
        print(f"BD creada: {PS_DB['database_name']} (id={db_id})")
        return db_id

    def ensure_dataset(self, db_id: int, table_name: str) -> int:
        q = {"filters": [{"col": "table_name", "opr": "eq", "value": table_name}]}
        res = self._request("GET", f"/api/v1/dataset/?q={urllib.parse.quote(json.dumps(q))}")
        for item in res.get("result") or []:
            if item.get("database", {}).get("id") == db_id:
                print(f"Dataset: {table_name} (id={item['id']})")
                return item["id"]
        ds_id = self._request(
            "POST",
            "/api/v1/dataset/",
            {"database": db_id, "schema": "public", "table_name": table_name},
        )["id"]
        print(f"Dataset creado: {table_name} (id={ds_id})")
        return ds_id

    def list_charts(self) -> list[dict[str, Any]]:
        res = self._request(
            "GET",
            "/api/v1/chart/?q=" + urllib.parse.quote(json.dumps({"page_size": 200})),
        )
        return res.get("result") or []

    def delete_chart(self, chart_id: int) -> None:
        try:
            self._request("DELETE", f"/api/v1/chart/{chart_id}")
        except RuntimeError:
            pass

    def upsert_chart(
        self,
        *,
        name: str,
        dataset_id: int,
        viz_type: str,
        params: dict[str, Any],
        existing_by_name: dict[str, int],
    ) -> int:
        payload = {
            "slice_name": name,
            "viz_type": viz_type,
            "datasource_id": dataset_id,
            "datasource_type": "table",
            "params": json.dumps(params),
        }
        if name in existing_by_name:
            cid = existing_by_name[name]
            self._request("PUT", f"/api/v1/chart/{cid}", payload)
            print(f"Chart actualizado: {name} (id={cid})")
            return cid
        cid = self._request("POST", "/api/v1/chart/", payload)["id"]
        print(f"Chart creado: {name} (id={cid})")
        return cid

    def find_dashboard(self) -> dict[str, Any] | None:
        # Preferir slug (estable); título puede cambiar entre regeneraciones.
        for col, value in (("slug", DASHBOARD_SLUG), ("dashboard_title", DASHBOARD_TITLE)):
            q = {"filters": [{"col": col, "opr": "eq", "value": value}]}
            res = self._request(
                "GET", f"/api/v1/dashboard/?q={urllib.parse.quote(json.dumps(q))}"
            )
            items = res.get("result") or []
            if items:
                return items[0]
        return None

    def attach_charts(self, dash_id: int, chart_ids: list[int]) -> None:
        for cid in chart_ids:
            self._request("PUT", f"/api/v1/chart/{cid}", {"dashboards": [dash_id]})


def apply_bi_views() -> None:
    if os.environ.get("SKIP_APPLY_BI_VIEWS", "").strip() in ("1", "true", "yes"):
        print("SKIP_APPLY_BI_VIEWS=1 — omitiendo apply-bi-views.sh")
        return
    script = ROOT / "scripts" / "apply-bi-views.sh"
    subprocess.run(["bash", str(script)], check=True)


def pull_ui_snapshot_before_push() -> None:
    """Trae estado UI de Superset y avisa si difiere del snapshot previous.

    Evita pisar edits manuales sin aviso. Override:
      SKIP_SUPERSET_PULL=1
      STRICT_UI_SYNC=1  → falla si hay divergencia vs previous
    """
    if os.environ.get("SKIP_SUPERSET_PULL", "").strip() in ("1", "true", "yes"):
        print("SKIP_SUPERSET_PULL=1 — omitiendo pull de UI")
        return
    pull_script = ROOT / "scripts" / "pull-superset-dashboard.py"
    if not pull_script.is_file():
        print(f"AVISO: no existe {pull_script.name}; continuo sin pull")
        return
    strict = os.environ.get("STRICT_UI_SYNC", "").strip() in ("1", "true", "yes")
    cmd = [sys.executable, str(pull_script)]
    if strict:
        cmd.append("--strict")
    print("==> 0/4 Pull estado UI Superset (snapshot)...")
    env = os.environ.copy()
    env.setdefault("SUPERSET_URL", SUPERSET_URL)
    env.setdefault("SUPERSET_USER", SUPERSET_USER)
    env.setdefault("SUPERSET_PASSWORD", SUPERSET_PASSWORD)
    result = subprocess.run(cmd, env=env, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "Pull UI detectó divergencias (STRICT_UI_SYNC=1) o falló. "
            "Revisa exports/superset-dashboard/latest/ o usa SKIP_SUPERSET_PULL=1."
        )


def metric_sum(column: str, label: str) -> dict[str, Any]:
    return {
        "expressionType": "SIMPLE",
        "column": {"column_name": column},
        "aggregate": "SUM",
        "label": label,
    }


def metric_sql(sql: str, label: str) -> dict[str, Any]:
    return {"expressionType": "SQL", "sqlExpression": sql, "label": label}


def dim_adhoc_filters(*extra_cols: str) -> list[dict[str, Any]]:
    """Fuerza a Superset 6.x a exponer dims en /dashboard/.../datasets
    (si no, Apply queda disabled en big_number / table).
    """
    out: list[dict[str, Any]] = []
    for col in ("year", "empresa", "department_code", *extra_cols):
        out.append(
            {
                "expressionType": "SIMPLE",
                "subject": col,
                "operator": "IS NOT NULL",
                "operatorId": "IS_NOT_NULL",
                "clause": "WHERE",
                "sqlExpression": None,
                "isExtra": False,
                "isNew": False,
                "datasourceWarning": False,
                "filterOptionName": f"filter_{col}_not_null",
            }
        )
    return out


def probabilidad_bar_params() -> dict[str, Any]:
    """Barras PBI: probabilidad (100..10) × facturación P+R.
    Superset 6.1: dist_bar legacy no está registrado → echarts_timeseries_bar.
    """
    return {
        "adhoc_filters": dim_adhoc_filters(),
        "x_axis": "probabilidad",
        "metrics": [metric_sum("facturacion", "Facturación")],
        "groupby": [],
        "orientation": "horizontal",
        "seriesType": "bar",
        "show_value": True,
        "y_axis_format": ",.0f",
        "x_axis_title": "%",
        "y_axis_title": "",
        "rich_tooltip": True,
        "show_legend": False,
        "row_limit": 20,
        "truncate_metric": True,
        "x_axis_sort_asc": False,
        "x_axis_sort_series": "name",
        "x_axis_sort_series_ascending": False,
        "color_scheme": "supersetColors",
    }


def resumen_mensual_params() -> dict[str, Any]:
    """Tabla PBI Resumen: AñoMes | Facturación | Coste | Margen % (agregada)."""
    return {
        "adhoc_filters": dim_adhoc_filters("tipo"),
        "query_mode": "aggregate",
        "groupby": ["ano_mes"],
        "metrics": [
            metric_sum("facturacion", "Facturación"),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": ['["ano_mes", true]'],
        "row_limit": 1000,
        # Sin page_length: evita el selector "Show N entries per page" (pocas filas/mes)
        "server_pagination": False,
        "show_totals": True,
        "include_search": False,
        "show_cell_bars": False,
        "color_pn": False,
        "align_pn": False,
        "table_timestamp_format": "smart_date",
        "column_config": {
            "ano_mes": {
                "customColumnName": "Año/Mes",
            },
            "Facturación": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Coste": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Margen %": {
                "d3NumberFormat": ".2f",
                "showCellBars": False,
            },
        },
    }


def resumen_proyectos_params() -> dict[str, Any]:
    """Tabla PBI Resumen Proyectos: Proyecto | Facturación | Coste | Margen %."""
    return {
        "adhoc_filters": dim_adhoc_filters("tipo"),
        "query_mode": "aggregate",
        "groupby": ["proyecto"],
        "metrics": [
            metric_sum("facturacion", "Facturación"),
            metric_sum("coste", "Coste"),
            metric_sql(
                "(SUM(facturacion) - SUM(coste)) / NULLIF(SUM(facturacion), 0) * 100",
                "Margen %",
            ),
        ],
        "percent_metrics": [],
        "order_by_cols": ['["Facturación", false]'],
        "row_limit": 5000,
        # Sin page_length: evita el selector "Show N entries per page"
        "server_pagination": False,
        "show_totals": True,
        "include_search": True,
        "show_cell_bars": False,
        "color_pn": True,
        "align_pn": False,
        "table_timestamp_format": "smart_date",
        "column_config": {
            "proyecto": {
                "customColumnName": "Proyectos",
                "columnWidth": 220,
            },
            "Facturación": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Coste": {
                "d3NumberFormat": ",.0f",
                "currencyFormat": {"symbol": "EUR", "symbolPosition": "suffix"},
                "showCellBars": False,
            },
            "Margen %": {
                "d3NumberFormat": ".2f",
                "showCellBars": False,
            },
        },
    }


def big_number_params(metric: dict[str, Any], fmt: str, *, currency: bool = False) -> dict[str, Any]:
    # header_font_size es factor × 16px; 1.25 ≈ 20px (Segoe UI solicitado)
    # subheader = etiqueta bajo el valor (Facturación, Margen, etc.) como en Power BI
    label = metric.get("label", "")
    params: dict[str, Any] = {
        "adhoc_filters": dim_adhoc_filters(),
        "metric": metric,
        "header_font_size": 0.9,
        "subheader": label,
        "subheader_font_size": 0.6,
        "y_axis_format": fmt,
    }
    if currency:
        params["currency_format"] = {"symbol": "EUR", "symbolPosition": "suffix"}
    return params


def get_chart_uuids(client: SupersetClient) -> dict[int, str]:
    """UUID de charts vía API (evita docker exec; usable desde Mac contra VM 100)."""
    uuids: dict[int, str] = {}
    for item in client.list_charts():
        cid = item.get("id")
        uuid = item.get("uuid")
        if cid is not None and uuid:
            uuids[int(cid)] = str(uuid)
    return uuids


def persist_dashboard_config(
    client: SupersetClient,
    dash_id: int,
    dataset_ids: dict[str, int],
    chart_ids: list[int],
) -> None:
    # KPI cards (bi_v_planificacion_kpi) exponen year/empresa/department_code vía
    # adhoc_filters IS NOT NULL (ver dim_adhoc_filters). Valores de filtro Tipo
    # siguen en bi_v_evolucion_mensual.
    detail_ds = dataset_ids["bi_v_planificacion_kpi"]
    evo_ds = dataset_ids["bi_v_evolucion_mensual"]
    kpi_chart_ids = chart_ids[:8]  # 8 tarjetas Obj/Plan
    # order: resumen mensual, proyectos, prob, evo, margen
    table_id = chart_ids[8]
    projects_id = chart_ids[9]
    prob_chart_ids = [chart_ids[10]] if len(chart_ids) > 10 else []
    evo_chart_ids = chart_ids[11:13]  # Evolución + Margen (filtro Tipo)
    filter_scope_all = (
        kpi_chart_ids + [table_id, projects_id] + evo_chart_ids + prob_chart_ids
    )

    dashboard_css = (
        "/* Power BI look: Segoe UI 20px en valor KPI */\n"
        ".dashboard, .dashboard .chart-slice, "
        ".superset-legacy-chart-big-number, "
        ".dashboard-markdown, .dashboard .header-title,\n"
        ".dashboard .editable-title a, .dashboard .editable-title input {\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "}\n"
        "/* === Estilo tarjetas (similar home Timesheet) === */\n"
        ".dashboard-content, .dashboard, "
        ".grid-content, .dashboard-grid,\n"
        ".dashboard .dragdroppable-row, "
        ".dashboard-component-tabs .ant-tabs-content-holder {\n"
        "  background: #eef2f4 !important;\n"
        "}\n"
        ".dashboard-component-tabs, "
        ".dashboard-component-tabs .ant-tabs-nav {\n"
        "  background: transparent !important;\n"
        "}\n"
        "/* Card base: blanca, radio, sombra suave */\n"
        ".dashboard-component-chart-holder {\n"
        "  border: 1px solid #e2e8ec !important;\n"
        "  border-radius: 12px !important;\n"
        "  background: #ffffff !important;\n"
        "  box-shadow: 0 1px 2px rgba(20, 59, 65, 0.06) !important;\n"
        "  box-sizing: border-box !important;\n"
        "  overflow: hidden !important;\n"
        "}\n"
        "/* KPI: barra lateral de acento + más padding */\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) {\n"
        "  border-left-width: 4px !important;\n"
        "  border-left-style: solid !important;\n"
        "  border-left-color: #143b41 !important;\n"
        "  padding: 10px 14px !important;\n"
        "  box-shadow: 0 1px 3px rgba(20, 59, 65, 0.08) !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Facturación'] {\n"
        "  border-left-color: #0d9488 !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Margen'] {\n"
        "  border-left-color: #2563eb !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Crecimiento'],\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Δ'] {\n"
        "  border-left-color: #f59e0b !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Beneficio'] {\n"
        "  border-left-color: #16a34a !important;\n"
        "}\n"
        "/* Charts/tablas: aire interno uniforme */\n"
        ".dashboard-component-chart-holder:not("
        ":has(.superset-legacy-chart-big-number)) {\n"
        "  padding: 8px !important;\n"
        "}\n"
        "/* Tablas: padding uniforme sin alterar el layout nativo del card */\n"
        ".dashboard-component-chart-holder[data-test-chart-name*='Resumen mensual'],\n"
        ".dashboard-component-chart-holder[data-test-chart-name*='Proyectos'] {\n"
        "  padding: 8px !important;\n"
        "}\n"
        "/* ⋮ visible alineado con el titulo — Superset 6.x usa data-test=slice-header */\n"
        ".dashboard-component-chart-holder[data-test-chart-name*='Resumen mensual']"
        " [data-test='slice-header'] .header-controls,\n"
        ".dashboard-component-chart-holder[data-test-chart-name*='Proyectos']"
        " [data-test='slice-header'] .header-controls {\n"
        "  display: flex !important;\n"
        "  align-items: center !important;\n"
        "}\n"
        "/* Valor KPI base */\n"
        ".superset-legacy-chart-big-number .header-line {\n"
        "  font-weight: 700 !important; color: #0f172a;\n"
        "  line-height: 1.2 !important; white-space: nowrap;\n"
        "}\n"
        "/* Euros (Facturación, Beneficio): 23px -5% → 22px */\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Facturación'] .header-line,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Beneficio'] .header-line,\n"
        ".superset-legacy-chart-big-number .header-line {\n"
        "  font-size: 22px !important;\n"
        "}\n"
        "/* Porcentajes (Margen, Crecimiento): 17px -5% → 16px */\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Margen'] .header-line,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "[data-test-chart-name*='Crecimiento'] .header-line {\n"
        "  font-size: 16px !important;\n"
        "}\n"
        "/* Ocultar botón/badge de filtros y controles extra en charts */\n"
        ".dashboard-component-chart-holder .filter-counts,\n"
        ".dashboard-component-chart-holder .filters-badge,\n"
        ".dashboard-component-chart-holder [data-test='filter-counts'],\n"
        ".dashboard-component-chart-holder .slice_header [aria-label*='ilter'],\n"
        ".dashboard-component-chart-holder .slice_header [aria-label*='iltro'],\n"
        ".dashboard-component-chart-holder .header-controls .filter-counts,\n"
        ".dashboard-component-chart-holder .header-controls .filters-badge,\n"
        ".dashboard-component-chart-holder .slice_header button[aria-label*='ilter'],\n"
        ".dashboard-component-chart-holder .slice_header button[aria-label*='iltro'],\n"
        ".dashboard-component-chart-holder .header-controls > :has(svg[data-icon='filter']),\n"
        ".dashboard-component-chart-holder .header-controls span[role='img'][aria-label*='ilter'],\n"
        ".dashboard-component-chart-holder .header-controls span[role='img'][aria-label*='iltro'] {\n"
        "  display: none !important;\n"
        "  width: 0 !important;\n"
        "  height: 0 !important;\n"
        "  min-width: 0 !important;\n"
        "  min-height: 0 !important;\n"
        "  margin: 0 !important;\n"
        "  padding: 0 !important;\n"
        "  overflow: hidden !important;\n"
        "  visibility: hidden !important;\n"
        "  pointer-events: none !important;\n"
        "}\n"
        "/* Ocultar cabecera KPI (título + menú ⋮); etiqueta va en subheader */\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) .slice_header,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) .header-title,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        " .header-controls,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        " .slice_header .controls,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        " .slice-header-controls,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        " [data-test='dashboard-slice-header-controls'] {\n"
        "  display: none !important;\n"
        "  height: 0 !important;\n"
        "  min-height: 0 !important;\n"
        "  margin: 0 !important;\n"
        "  padding: 0 !important;\n"
        "  overflow: hidden !important;\n"
        "}\n"
        "/* Etiqueta bajo el valor: 16px -5% → 15px */\n"
        ".superset-legacy-chart-big-number .subheader-line {\n"
        "  font-size: 11px !important; font-weight: 600 !important;\n"
        "  letter-spacing: 0.02em !important;\n"
        "  text-transform: uppercase !important;\n"
        "  color: #64748b !important;\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "  text-align: left !important; margin-top: 4px !important;\n"
        "}\n"
        "/* Titulos charts/tablas: teal bold estilo Timesheet (Lista de Notas) */\n"
        ".dashboard-component-chart-holder .header-title,\n"
        ".dashboard-component-chart-holder .header-title a,\n"
        ".dashboard-component-chart-holder .editable-title,\n"
        ".dashboard-component-chart-holder .editable-title a,\n"
        ".dashboard-component-chart-holder .editable-title input,\n"
        ".dashboard-component-chart-holder .editable-title span {\n"
        "  font-size: 16px !important;\n"
        "  font-weight: 700 !important;\n"
        "  color: #007c89 !important;\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "  letter-spacing: 0 !important;\n"
        "  line-height: 1.25 !important;\n"
        "}\n"
        "/* Cabeceras de seccion: HEADER nativo (sin scroll markdown) */\n"
        ".dashboard-component-header,\n"
        ".dashboard-component-header .header-controls,\n"
        ".dashboard-component-header .editable-title,\n"
        ".dashboard-component-header .editable-title input,\n"
        ".dashboard-component-header .editable-title span,\n"
        ".dashboard-component-header h1,\n"
        ".dashboard-component-header h2,\n"
        ".dashboard-component-header h3 {\n"
        "  overflow: hidden !important;\n"
        "  overflow-y: hidden !important;\n"
        "  scrollbar-width: none !important;\n"
        "  -ms-overflow-style: none !important;\n"
        "}\n"
        ".dashboard-component-header {\n"
        "  display: flex !important;\n"
        "  align-items: center !important;\n"
        "  justify-content: flex-start !important;\n"
        "  height: 100% !important;\n"
        "  max-height: 100% !important;\n"
        "  margin: 0 !important;\n"
        "  padding: 0 8px !important;\n"
        "  box-sizing: border-box !important;\n"
        "}\n"
        ".dashboard-component-header *::-webkit-scrollbar {\n"
        "  width: 0 !important; height: 0 !important; display: none !important;\n"
        "}\n"
        ".dashboard-component-header .editable-title,\n"
        ".dashboard-component-header .editable-title input,\n"
        ".dashboard-component-header .editable-title span,\n"
        ".dashboard-component-header h1,\n"
        ".dashboard-component-header h2,\n"
        ".dashboard-component-header h3 {\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "  font-size: 18px !important; font-weight: 700 !important; color: #007c89 !important;\n"
        "  margin: 0 !important; padding: 0 !important;\n"
        "  line-height: 1.15 !important;\n"
        "  height: auto !important;\n"
        "}\n"
        "/* Fallback si quedara algun markdown de cabecera */\n"
        ".dashboard-component-chart-holder:has(.dashboard-markdown),\n"
        ".dashboard-component-chart-holder:has(.dashboard-markdown) .dashboard-markdown,\n"
        ".dashboard-component-chart-holder:has(.dashboard-markdown) .markdown-content,\n"
        ".dashboard-component-chart-holder:has(.dashboard-markdown) .renderedMarkdown {\n"
        "  overflow: hidden !important;\n"
        "  overflow-y: clip !important;\n"
        "  scrollbar-width: none !important;\n"
        "  max-height: 100% !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.dashboard-markdown) *::-webkit-scrollbar {\n"
        "  width: 0 !important; height: 0 !important; display: none !important;\n"
        "}\n"
        "/* Tarjetas KPI: centrado vertical + sin scroll */\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) {\n"
        "  overflow: hidden !important;\n"
        "  scrollbar-width: none !important;\n"
        "  display: flex !important;\n"
        "  flex-direction: column !important;\n"
        "  justify-content: center !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number)"
        "::-webkit-scrollbar {\n"
        "  width: 0 !important; height: 0 !important; display: none !important;\n"
        "}\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) .chart-slice,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) .slice_container,\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) .hashbox {\n"
        "  overflow: hidden !important;\n"
        "  scrollbar-width: none !important;\n"
        "  display: flex !important;\n"
        "  flex-direction: column !important;\n"
        "  justify-content: center !important;\n"
        "  height: 100% !important;\n"
        "  width: 100% !important;\n"
        "  flex: 1 1 auto !important;\n"
        "  min-height: 0 !important;\n"
        "  margin: 0 !important;\n"
        "  padding: 0 !important;\n"
        "}\n"
        ".superset-legacy-chart-big-number {\n"
        "  display: flex !important;\n"
        "  flex-direction: column !important;\n"
        "  justify-content: center !important;\n"
        "  align-items: flex-start !important;\n"
        "  height: 100% !important;\n"
        "  width: 100% !important;\n"
        "  overflow: hidden !important;\n"
        "}\n"
        ".superset-legacy-chart-big-number .header-line,\n"
        ".superset-legacy-chart-big-number .subheader-line {\n"
        "  text-align: left !important;\n"
        "  overflow: hidden !important;\n"
        "}\n"
        "/* Tablas estilo Timesheet (rejilla + separadores verticales) */\n"
        "[data-test-chart-name*='Resumen mensual'] table,\n"
        "[data-test-chart-name*='Proyectos'] table,\n"
        "[data-test-chart-name*='Resumen mensual'] .table,\n"
        "[data-test-chart-name*='Proyectos'] .table {\n"
        "  border-collapse: separate !important;\n"
        "  border-spacing: 0 !important;\n"
        "  width: 100% !important;\n"
        "  background: #ffffff !important;\n"
        "  border: 1px solid #d1d5db !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] th,\n"
        "[data-test-chart-name*='Proyectos'] th,\n"
        "[data-test-chart-name*='Resumen mensual'] td,\n"
        "[data-test-chart-name*='Proyectos'] td,\n"
        "[data-test-chart-name*='Resumen mensual'] .ant-table-thead > tr > th,\n"
        "[data-test-chart-name*='Proyectos'] .ant-table-thead > tr > th,\n"
        "[data-test-chart-name*='Resumen mensual'] .ant-table-tbody > tr > td,\n"
        "[data-test-chart-name*='Proyectos'] .ant-table-tbody > tr > td,\n"
        "[data-test-chart-name*='Resumen mensual'] thead th,\n"
        "[data-test-chart-name*='Proyectos'] thead th {\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "  font-size: 13px !important;\n"
        "  line-height: 1.35 !important;\n"
        "  border-top: 1px solid #e5e7eb !important;\n"
        "  border-bottom: 1px solid #e5e7eb !important;\n"
        "  border-left: 1px solid #d1d5db !important;\n"
        "  border-right: 1px solid #d1d5db !important;\n"
        "  box-shadow: none !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] th,\n"
        "[data-test-chart-name*='Proyectos'] th,\n"
        "[data-test-chart-name*='Resumen mensual'] .ant-table-thead > tr > th,\n"
        "[data-test-chart-name*='Proyectos'] .ant-table-thead > tr > th,\n"
        "[data-test-chart-name*='Resumen mensual'] thead th,\n"
        "[data-test-chart-name*='Proyectos'] thead th {\n"
        "  background: #f3f4f6 !important;\n"
        "  color: #374151 !important;\n"
        "  font-weight: 600 !important;\n"
        "  padding: 10px 12px !important;\n"
        "  height: auto !important;\n"
        "  background-image: none !important;\n"
        "  text-align: left !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] td,\n"
        "[data-test-chart-name*='Proyectos'] td,\n"
        "[data-test-chart-name*='Resumen mensual'] .ant-table-tbody > tr > td,\n"
        "[data-test-chart-name*='Proyectos'] .ant-table-tbody > tr > td {\n"
        "  background: #ffffff !important;\n"
        "  color: #111827 !important;\n"
        "  padding: 10px 12px !important;\n"
        "  height: auto !important;\n"
        "  background-image: none !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] tbody tr:hover td,\n"
        "[data-test-chart-name*='Proyectos'] tbody tr:hover td,\n"
        "[data-test-chart-name*='Resumen mensual'] .ant-table-tbody > tr:hover > td,\n"
        "[data-test-chart-name*='Proyectos'] .ant-table-tbody > tr:hover > td {\n"
        "  background: #f9fafb !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] .cell-bar,\n"
        "[data-test-chart-name*='Resumen mensual'] .cell-bars,\n"
        "[data-test-chart-name*='Resumen mensual'] td > div[style*='background'],\n"
        "[data-test-chart-name*='Resumen mensual'] .dt-cell-bar,\n"
        "[data-test-chart-name*='Proyectos'] .cell-bar,\n"
        "[data-test-chart-name*='Proyectos'] .cell-bars,\n"
        "[data-test-chart-name*='Proyectos'] td > div[style*='background'],\n"
        "[data-test-chart-name*='Proyectos'] .dt-cell-bar {\n"
        "  display: none !important;\n"
        "  background: none !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] .slice_container,\n"
        "[data-test-chart-name*='Proyectos'] .slice_container {\n"
        "  flex: 1 1 auto !important;\n"
        "  min-height: 0 !important;\n"
        "  padding: 0 !important;\n"
        "  margin: 0 !important;\n"
        "  width: 100% !important;\n"
        "  max-width: 100% !important;\n"
        "  box-sizing: border-box !important;\n"
        "  overflow-y: auto !important;\n"
        "  overflow-x: hidden !important;\n"
        "  scrollbar-width: none !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] .slice_container::-webkit-scrollbar,\n"
        "[data-test-chart-name*='Proyectos'] .slice_container::-webkit-scrollbar {\n"
        "  width: 0 !important;\n"
        "  height: 0 !important;\n"
        "  display: none !important;\n"
        "}\n"
        "/* Cabeceras de tabla: sin wrap para que quepan en 1 línea */\n"
        "[data-test-chart-name*='Resumen mensual'] thead th,\n"
        "[data-test-chart-name*='Proyectos'] thead th {\n"
        "  white-space: nowrap !important;\n"
        "}\n"
        "[data-test-chart-name*='Resumen mensual'] table,\n"
        "[data-test-chart-name*='Proyectos'] table,\n"
        "[data-test-chart-name*='Resumen mensual'] .table-condensed,\n"
        "[data-test-chart-name*='Proyectos'] .table-condensed,\n"
        "[data-test-chart-name*='Resumen mensual'] .dt-bootstrap,\n"
        "[data-test-chart-name*='Proyectos'] .dt-bootstrap {\n"
        "  width: 100% !important;\n"
        "  max-width: 100% !important;\n"
        "  margin: 0 !important;\n"
        "  box-sizing: border-box !important;\n"
        "}\n"
        "/* Tablas: ocultar selector Show N entries per page */\n"
        "[data-test-chart-name*='Resumen mensual'] .dt-length,\n"
        "[data-test-chart-name*='Resumen mensual'] .dataTables_length,\n"
        "[data-test-chart-name*='Resumen mensual'] .ant-pagination,\n"
        "[data-test-chart-name*='Resumen mensual'] .pagination-container,\n"
        "[data-test-chart-name*='Resumen mensual'] select[aria-label*='page'],\n"
        "[data-test-chart-name*='Resumen mensual'] .row-count-container,\n"
        "[data-test-chart-name*='Proyectos'] .dt-length,\n"
        "[data-test-chart-name*='Proyectos'] .dataTables_length,\n"
        "[data-test-chart-name*='Proyectos'] .ant-pagination,\n"
        "[data-test-chart-name*='Proyectos'] .pagination-container,\n"
        "[data-test-chart-name*='Proyectos'] select[aria-label*='page'],\n"
        "[data-test-chart-name*='Proyectos'] .row-count-container {\n"
        "  display: none !important;\n"
        "}\n"
        "/* Tablas: fila Total (summary) siempre visible al pie */\n"
        "[data-test-chart-name*='Proyectos'] tfoot,\n"
        "[data-test-chart-name*='Proyectos'] .dt-totals,\n"
        "[data-test-chart-name='Proyectos'] tfoot,\n"
        "[data-test-chart-name*='Resumen mensual'] tfoot,\n"
        "[data-test-chart-name*='Resumen mensual'] .dt-totals,\n"
        "[data-test-chart-name='Resumen mensual'] tfoot {\n"
        "  display: table-footer-group !important;\n"
        "  position: sticky !important;\n"
        "  bottom: 0 !important;\n"
        "  background: #f3f4f6 !important;\n"
        "  font-weight: 700 !important;\n"
        "  z-index: 2 !important;\n"
        "}\n"
        "[data-test-chart-name*='Proyectos'] tfoot th,\n"
        "[data-test-chart-name*='Proyectos'] tfoot td,\n"
        "[data-test-chart-name*='Resumen mensual'] tfoot th,\n"
        "[data-test-chart-name*='Resumen mensual'] tfoot td {\n"
        "  border-top: 1px solid #e5e7eb !important;\n"
        "  border-bottom: 1px solid #e5e7eb !important;\n"
        "  border-left: 1px solid #d1d5db !important;\n"
        "  border-right: 1px solid #d1d5db !important;\n"
        "  background: #f3f4f6 !important;\n"
        "  padding: 10px 12px !important;\n"
        "}\n"
    )

    # Superset 6.1: IDs DEBEN empezar por NATIVE_FILTER- (isFilterId en FiltersConfigModal).
    json_metadata = {
        "cross_filters_enabled": False,
        "chart_configuration": {},
        "default_filters": "{}",
        "native_filter_configuration": [
            {
                "id": "NATIVE_FILTER-YEAR",
                "name": "Año",
                "filterType": "filter_select",
                "type": "NATIVE_FILTER",
                "targets": [{"datasetId": detail_ds, "column": {"name": "year"}}],
                "defaultDataMask": {
                    "filterState": {"value": [CURRENT_YEAR]},
                    "extraFormData": {
                        "filters": [{"col": "year", "op": "IN", "val": [CURRENT_YEAR]}]
                    },
                },
                "controlValues": {"multiSelect": False, "enableEmptyFilter": False},
                "cascadeParentIds": [],
                "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
                "chartsInScope": filter_scope_all,
                "tabsInScope": ["TAB-RESUMEN", "TAB-GRAFICOS"],
            },
            {
                "id": "NATIVE_FILTER-EMPRESA",
                "name": "Empresas",
                "filterType": "filter_select",
                "type": "NATIVE_FILTER",
                "targets": [{"datasetId": detail_ds, "column": {"name": "empresa"}}],
                "defaultDataMask": {
                    "filterState": {"value": [DEFAULT_EMPRESA]},
                    "extraFormData": {
                        "filters": [
                            {"col": "empresa", "op": "IN", "val": [DEFAULT_EMPRESA]}
                        ]
                    },
                },
                "controlValues": {
                    "multiSelect": True,
                    "enableEmptyFilter": False,
                    "sortAscending": True,
                },
                "cascadeParentIds": [],
                "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
                "chartsInScope": filter_scope_all,
                "tabsInScope": ["TAB-RESUMEN", "TAB-GRAFICOS"],
            },
            {
                "id": "NATIVE_FILTER-DEPT",
                "name": "Departamentos",
                "filterType": "filter_select",
                "type": "NATIVE_FILTER",
                "targets": [
                    {"datasetId": detail_ds, "column": {"name": "department_code"}}
                ],
                "defaultDataMask": {"filterState": {"value": None}},
                "controlValues": {
                    "multiSelect": True,
                    "enableEmptyFilter": False,
                    "sortAscending": True,
                },
                "cascadeParentIds": [],
                "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
                "chartsInScope": filter_scope_all,
                "tabsInScope": ["TAB-RESUMEN", "TAB-GRAFICOS"],
            },
            {
                "id": "NATIVE_FILTER-TIPO",
                "name": "Tipo P/R",
                "filterType": "filter_select",
                "type": "NATIVE_FILTER",
                "targets": [{"datasetId": evo_ds, "column": {"name": "tipo"}}],
                "defaultDataMask": {"filterState": {"value": None}},
                "controlValues": {"multiSelect": False, "enableEmptyFilter": False},
                "cascadeParentIds": [],
                "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
                "chartsInScope": evo_chart_ids + [table_id, projects_id],
                "tabsInScope": ["TAB-RESUMEN", "TAB-GRAFICOS"],
            },
        ],
    }
    client._request(
        "PUT",
        f"/api/v1/dashboard/{dash_id}",
        {
            "json_metadata": json.dumps(json_metadata),
            "css": dashboard_css,
        },
    )
    print(
        f"Dashboard config persistida vía API "
        f"(filtros evo_ds={evo_ds} + KPI detail_ds={detail_ds})"
    )


def build_layout(charts: list[dict[str, Any]]) -> dict[str, Any]:
    """Layout con pestañas: Resumen (KPI+tablas) | Gráficos (evolución)."""
    obj_keys = [c["key"] for c in charts if c["section"] == "obj"]
    plan_keys = [c["key"] for c in charts if c["section"] == "plan"]
    table_keys = [c["key"] for c in charts if c["section"] == "table"]
    projects_keys = [c["key"] for c in charts if c["section"] == "projects"]
    prob_keys = [c["key"] for c in charts if c["section"] == "prob"]
    chart_keys = [c["key"] for c in charts if c["section"] == "chart"]
    prob_key = prob_keys[0] if prob_keys else None

    # Euros (Facturación/Beneficio)=2; % =1 → columna 6. Probabilidad = 6.
    kpi_col_width = 6
    tab_resumen = ["ROOT_ID", "GRID_ID", "TABS-MAIN", "TAB-RESUMEN"]
    tab_graficos = ["ROOT_ID", "GRID_ID", "TABS-MAIN", "TAB-GRAFICOS"]
    col_parents = tab_resumen + ["ROW-KPI-BAND", "COLUMN-KPIS"]
    position: dict[str, Any] = {
        "DASHBOARD_VERSION": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID": {
            "type": "GRID",
            "id": "GRID_ID",
            "children": ["TABS-MAIN"],
            "parents": ["ROOT_ID"],
        },
        "TABS-MAIN": {
            "type": "TABS",
            "id": "TABS-MAIN",
            "children": ["TAB-RESUMEN", "TAB-GRAFICOS"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {},
        },
        "TAB-RESUMEN": {
            "type": "TAB",
            "id": "TAB-RESUMEN",
            "children": ["ROW-KPI-BAND", "ROW-TABLES"],
            "parents": ["ROOT_ID", "GRID_ID", "TABS-MAIN"],
            "meta": {"text": "Resumen", "defaultText": "Resumen"},
        },
        "TAB-GRAFICOS": {
            "type": "TAB",
            "id": "TAB-GRAFICOS",
            "children": ["ROW-CHARTS"],
            "parents": ["ROOT_ID", "GRID_ID", "TABS-MAIN"],
            "meta": {"text": "Gráficos", "defaultText": "Gráficos"},
        },
        "ROW-KPI-BAND": {
            "type": "ROW",
            "id": "ROW-KPI-BAND",
            "children": (["COLUMN-KPIS"] + ([prob_key] if prob_key else [])),
            "parents": list(tab_resumen),
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "COLUMN-KPIS": {
            "type": "COLUMN",
            "id": "COLUMN-KPIS",
            "children": ["ROW-HDR-OBJ", "ROW-OBJ", "ROW-HDR-PLAN", "ROW-PLAN"],
            "parents": tab_resumen + ["ROW-KPI-BAND"],
            "meta": {"background": "BACKGROUND_TRANSPARENT", "width": kpi_col_width},
        },
        "ROW-HDR-OBJ": {
            "type": "ROW", "id": "ROW-HDR-OBJ", "children": ["HEADER-OBJ"],
            "parents": col_parents,
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-HDR-PLAN": {
            "type": "ROW", "id": "ROW-HDR-PLAN", "children": ["HEADER-PLAN"],
            "parents": col_parents,
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "HEADER-OBJ": {
            "type": "HEADER", "id": "HEADER-OBJ", "children": [],
            "parents": col_parents + ["ROW-HDR-OBJ"],
            "meta": {
                "text": "Objetivos Anuales",
                "headerSize": "MEDIUM_HEADER",
                "width": kpi_col_width,
                "height": 4,
            },
        },
        "HEADER-PLAN": {
            "type": "HEADER", "id": "HEADER-PLAN", "children": [],
            "parents": col_parents + ["ROW-HDR-PLAN"],
            "meta": {
                "text": "Planificación Actual",
                "headerSize": "MEDIUM_HEADER",
                "width": kpi_col_width,
                "height": 4,
            },
        },
        "ROW-OBJ": {
            "type": "ROW", "id": "ROW-OBJ",
            "children": obj_keys,
            "parents": col_parents,
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-PLAN": {
            "type": "ROW", "id": "ROW-PLAN",
            "children": plan_keys,
            "parents": col_parents,
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-TABLES": {
            "type": "ROW", "id": "ROW-TABLES",
            "children": table_keys + projects_keys,
            "parents": list(tab_resumen),
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-CHARTS": {
            "type": "ROW", "id": "ROW-CHARTS",
            "children": chart_keys,
            "parents": list(tab_graficos),
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
    }
    sizes = {
        # Alturas UI: KPI 10; tablas Resumen/Proyectos misma altura; charts 36.
        "obj": (1, 10),
        "plan": (1, 10),
        "table": (4, 53),
        "projects": (8, 53),
        "prob": (6, 36),
        "chart": (6, 36),
    }
    # Importes grandes (euros) más anchos; % compactos
    kpi_widths = {"Facturación": 2, "Margen": 1, "Δ %": 1, "Crecimiento": 1, "Beneficio": 2}
    for c in charts:
        w, h = sizes[c["section"]]
        display_name = c["name"].split("· ")[-1]
        if display_name == "Crecimiento":
            display_name = "Δ %"
        if c["section"] == "prob":
            display_name = "Facturación por Probabilidad"
            parents = tab_resumen + ["ROW-KPI-BAND"]
        elif c["section"] in ("obj", "plan"):
            parents = col_parents + [
                "ROW-OBJ" if c["section"] == "obj" else "ROW-PLAN",
            ]
            w = kpi_widths.get(display_name, 1)
        elif c["section"] in ("table", "projects"):
            if c["section"] == "projects":
                display_name = "Proyectos"
            parents = tab_resumen + ["ROW-TABLES"]
        else:
            parents = tab_graficos + ["ROW-CHARTS"]
        position[c["key"]] = {
            "type": "CHART", "id": c["key"], "children": [],
            "parents": parents,
            "meta": {
                "width": w, "height": h,
                "chartId": c["id"], "uuid": c.get("uuid", ""),
                "sliceName": display_name,
                "sliceNameOverride": display_name,
            },
        }
    return position


def main() -> int:
    pull_ui_snapshot_before_push()

    print("==> 1/4 Aplicando vistas BI en PostgreSQL...")
    apply_bi_views()

    client = SupersetClient()
    client.login()
    print("Login Superset OK")

    print("==> 2/4 Creando datasets...")
    db_id = client.ensure_database()
    dataset_ids = {name: client.ensure_dataset(db_id, name) for name in DATASETS}
    # Tarjetas KPI: bi_v_planificacion_kpi (tiene department_code + real_anterior)
    kpi_ds = dataset_ids["bi_v_planificacion_kpi"]
    evo_ds = dataset_ids["bi_v_evolucion_mensual"]
    prob_ds = dataset_ids["bi_v_facturacion_probabilidad"]
    proy_ds = dataset_ids["bi_v_resumen_proyectos"]

    print("==> 3/4 Creando charts...")
    existing = {c["slice_name"]: c["id"] for c in client.list_charts()}
    stale_names = set(existing) - {
        "Obj · Facturación", "Obj · Margen", "Obj · Crecimiento", "Obj · Beneficio",
        "Plan · Facturación", "Plan · Margen", "Plan · Crecimiento", "Plan · Beneficio",
        "Resumen mensual", "Proyectos", "Evolución mensual", "Margen acumulado",
        "Facturación por Probabilidad",
        "Facturación", "Margen", "Crecimiento", "Beneficio", "Δ %",
    }
    for name in stale_names:
        if name.startswith(("Obj", "Plan")) or "Planificación" in name:
            client.delete_chart(existing[name])

    chart_specs: list[tuple[str, str, int, str, dict[str, Any]]] = [
        ("Obj · Facturación", "obj", kpi_ds, "big_number_total",
         big_number_params(metric_sum("obj_facturacion", "Facturación"), ",.0f", currency=True)),
        ("Obj · Margen", "obj", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql("SUM(obj_beneficio)/NULLIF(SUM(obj_facturacion),0)", "Margen"), ".2%")),
        ("Obj · Crecimiento", "obj", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql(
                 "(SUM(obj_facturacion)-SUM(facturacion_real_anterior))"
                 "/NULLIF(SUM(facturacion_real_anterior),0)",
                 "Δ %"),
             ".2%")),
        ("Obj · Beneficio", "obj", kpi_ds, "big_number_total",
         big_number_params(metric_sum("obj_beneficio", "Beneficio"), ",.0f", currency=True)),
        ("Plan · Facturación", "plan", kpi_ds, "big_number_total",
         big_number_params(metric_sum("plan_facturacion", "Facturación"), ",.0f", currency=True)),
        ("Plan · Margen", "plan", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql("SUM(plan_beneficio)/NULLIF(SUM(plan_facturacion),0)", "Margen"), ".2%")),
        ("Plan · Crecimiento", "plan", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql(
                 "(SUM(plan_facturacion)-SUM(facturacion_real_anterior))"
                 "/NULLIF(SUM(facturacion_real_anterior),0)",
                 "Δ %"),
             ".2%")),
        ("Plan · Beneficio", "plan", kpi_ds, "big_number_total",
         big_number_params(metric_sum("plan_beneficio", "Beneficio"), ",.0f", currency=True)),
        ("Resumen mensual", "table", evo_ds, "table", resumen_mensual_params()),
        # PBI Resumen Proyectos: Operational + estado Completed/Open/Planning
        ("Proyectos", "projects", proy_ds, "table", resumen_proyectos_params()),
        ("Facturación por Probabilidad", "prob", prob_ds, "echarts_timeseries_bar",
         probabilidad_bar_params()),
        ("Evolución mensual", "chart", evo_ds, "echarts_timeseries_line",
         {"adhoc_filters": dim_adhoc_filters("tipo"),
          "x_axis": "ano_mes", "metrics": [metric_sum("facturacion", "Facturación")],
          "groupby": [], "row_limit": 1000}),
        ("Margen acumulado", "chart", evo_ds, "echarts_timeseries_line",
         {"adhoc_filters": dim_adhoc_filters("tipo"),
          "x_axis": "ano_mes",
          "metrics": [metric_sql("AVG(margen_pct)", "Margen %")],
          "row_limit": 1000}),
    ]

    charts: list[dict[str, Any]] = []
    for idx, (name, section, ds_id, viz, params) in enumerate(chart_specs, start=1):
        cid = client.upsert_chart(
            name=name, dataset_id=ds_id, viz_type=viz, params=params,
            existing_by_name=existing,
        )
        charts.append({"key": f"CHART-{idx}", "id": cid, "name": name, "section": section})
        existing[name] = cid

    uuids = get_chart_uuids(client)
    for c in charts:
        c["uuid"] = uuids.get(c["id"], "")
        if not c["uuid"]:
            detail = client._request("GET", f"/api/v1/chart/{c['id']}")
            c["uuid"] = str((detail.get("result") or {}).get("uuid") or "")

    print("==> 4/4 Configurando dashboard...")
    existing_dash = client.find_dashboard()
    if existing_dash:
        dash_id = existing_dash["id"]
        client._request("PUT", f"/api/v1/dashboard/{dash_id}", {
            "dashboard_title": DASHBOARD_TITLE,
            "slug": DASHBOARD_SLUG,
            "published": True,
            "position_json": json.dumps(build_layout(charts)),
        })
    else:
        dash_id = client._request("POST", "/api/v1/dashboard/", {
            "dashboard_title": DASHBOARD_TITLE,
            "slug": DASHBOARD_SLUG,
            "published": True,
            "position_json": json.dumps(build_layout(charts)),
        })["id"]

    client.attach_charts(dash_id, [c["id"] for c in charts])
    persist_dashboard_config(
        client, dash_id, dataset_ids, [c["id"] for c in charts]
    )

    print(f"\n✅ Dashboard listo: {SUPERSET_URL}/superset/dashboard/{DASHBOARD_SLUG}/")
    print(f"   Año por defecto: {CURRENT_YEAR}")
    print("   Fuente de datos: scripts/sql/bi_dashboard_planificacion_views.sql")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
