#!/usr/bin/env python3
"""Configura Superset con capa BI mantenible (mismos datos que PBI/Metabase).

Flujo:
  1. Aplica vistas SQL bi_v_* en PostgreSQL
  2. Crea datasets físicos (sin SQL embebido en Python)
  3. Crea tarjetas KPI + tablas + gráficos
  4. Persiste filtros (año actual por defecto) vía ORM
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
SUPERSET_URL = os.environ.get("SUPERSET_URL", "http://localhost:8088").rstrip("/")
SUPERSET_USER = os.environ.get("SUPERSET_USER", "admin")
SUPERSET_PASSWORD = os.environ.get("SUPERSET_PASSWORD", "PsSuperset#2026xK9!")
CURRENT_YEAR = datetime.date.today().year
DASHBOARD_TITLE = "Planificación PS Analytics"
DASHBOARD_SLUG = "planificacion-ps-analytics"

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
        q = {"filters": [{"col": "dashboard_title", "opr": "eq", "value": DASHBOARD_TITLE}]}
        res = self._request("GET", f"/api/v1/dashboard/?q={urllib.parse.quote(json.dumps(q))}")
        items = res.get("result") or []
        return items[0] if items else None

    def attach_charts(self, dash_id: int, chart_ids: list[int]) -> None:
        for cid in chart_ids:
            self._request("PUT", f"/api/v1/chart/{cid}", {"dashboards": [dash_id]})


def apply_bi_views() -> None:
    script = ROOT / "scripts" / "apply-bi-views.sh"
    subprocess.run(["bash", str(script)], check=True)


def metric_sum(column: str, label: str) -> dict[str, Any]:
    return {
        "expressionType": "SIMPLE",
        "column": {"column_name": column},
        "aggregate": "SUM",
        "label": label,
    }


def metric_sql(sql: str, label: str) -> dict[str, Any]:
    return {"expressionType": "SQL", "sqlExpression": sql, "label": label}


def big_number_params(metric: dict[str, Any], fmt: str, *, currency: bool = False) -> dict[str, Any]:
    # header_font_size es factor × 16px; 1.25 ≈ 20px (Segoe UI solicitado)
    # subheader = etiqueta bajo el valor (Facturación, Margen, etc.) como en Power BI
    label = metric.get("label", "")
    params: dict[str, Any] = {
        "adhoc_filters": [],
        "metric": metric,
        "header_font_size": 0.9,
        "subheader": label,
        "subheader_font_size": 0.6,
        "y_axis_format": fmt,
    }
    if currency:
        params["currency_format"] = {"symbol": "EUR", "symbolPosition": "suffix"}
    return params


def get_chart_uuids() -> dict[int, str]:
    code = (
        "from superset.app import create_app;"
        "app=create_app();ctx=app.app_context();ctx.push();"
        "from superset.models.slice import Slice;"
        "from superset import db;"
        "print('\\n'.join(f'{s.id}\\t{s.uuid}' for s in db.session.query(Slice).all()))"
    )
    out = subprocess.run(
        ["docker", "exec", "superset", "python", "-c", code],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    uuids: dict[int, str] = {}
    for line in out.splitlines():
        parts = line.strip().split("\t")
        if len(parts) == 2 and parts[0].isdigit():
            uuids[int(parts[0])] = parts[1]
    return uuids


def persist_dashboard_config(dash_id: int, dataset_ids: dict[str, int], chart_ids: list[int]) -> None:
    kpi_ds = dataset_ids["bi_v_kpi_anual_empresa"]
    detail_ds = dataset_ids["bi_v_planificacion_kpi"]
    evo_ds = dataset_ids["bi_v_evolucion_mensual"]

    dashboard_css = (
        "/* Power BI look: Segoe UI 20px en valor KPI */\n"
        ".dashboard, .dashboard .chart-slice, "
        ".superset-legacy-chart-big-number, "
        ".dashboard-markdown, .dashboard .header-title,\n"
        ".dashboard .editable-title a, .dashboard .editable-title input {\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "}\n"
        "/* Valor KPI base */\n"
        ".superset-legacy-chart-big-number .header-line {\n"
        "  font-weight: 700 !important; color: #143b41;\n"
        "  line-height: 1.2 !important; white-space: nowrap;\n"
        "}\n"
        "/* Euros (Facturación, Beneficio): numero mas grande */\n"
        "[data-test-chart-name*='Facturación'] .header-line,\n"
        "[data-test-chart-name*='Beneficio'] .header-line {\n"
        "  font-size: 18px !important;\n"
        "}\n"
        "/* Porcentajes (Margen, Crecimiento): numero mas pequeno */\n"
        "[data-test-chart-name*='Margen'] .header-line,\n"
        "[data-test-chart-name*='Crecimiento'] .header-line {\n"
        "  font-size: 13px !important;\n"
        "}\n"
        "/* Ocultar titulo superior en tarjetas KPI; la etiqueta va en subheader */\n"
        ".dashboard-component-chart-holder:has(.superset-legacy-chart-big-number) .header-title {\n"
        "  display: none !important;\n"
        "}\n"
        "/* Etiqueta bajo el valor: Segoe UI 12px (como Power BI) */\n"
        ".superset-legacy-chart-big-number .subheader-line {\n"
        "  font-size: 12px !important; font-weight: 600 !important; color: #5f7377 !important;\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "  text-align: center !important; margin-top: 2px !important;\n"
        "}\n"
        "/* Titulo de graficos no-KPI */\n"
        ".dashboard-component-chart-holder .header-title,\n"
        ".dashboard-component-chart-holder .editable-title a,\n"
        ".dashboard-component-chart-holder .editable-title input {\n"
        "  font-size: 12px !important; font-weight: 600 !important; color: #5f7377 !important;\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "}\n"
        "/* Cabeceras de seccion */\n"
        ".dashboard-markdown h2 {\n"
        "  font-family: 'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif !important;\n"
        "  font-size: 20px !important; font-weight: 700 !important; color: #143b41;\n"
        "  margin: 4px 0 !important;\n"
        "}\n"
        "/* Tarjetas KPI compactas */\n"
        ".dashboard-component-chart-holder {\n"
        "  padding: 4px 8px !important;\n"
        "}\n"
    )
    code = f"""
from superset.app import create_app
import json

app = create_app()
with app.app_context():
    from superset import db
    from superset.models.dashboard import Dashboard

    dash = db.session.query(Dashboard).get({dash_id})
    jm = json.loads(dash.json_metadata or '{{}}')
    jm['native_filter_configuration'] = [
        {{
            'id': 'FILTER-YEAR',
            'name': 'Año',
            'filterType': 'filter_select',
            'type': 'NATIVE_FILTER',
            'targets': [{{'datasetId': {kpi_ds}, 'column': {{'name': 'year'}}}}],
            'defaultDataMask': {{
                'filterState': {{'value': [{CURRENT_YEAR}]}},
                'extraFormData': {{'filters': [{{'col': 'year', 'op': 'IN', 'val': [{CURRENT_YEAR}]}}]}},
            }},
            'controlValues': {{'multiSelect': False, 'enableEmptyFilter': False}},
            'scope': {{'rootPath': ['ROOT_ID'], 'excluded': []}},
        }},
        {{
            'id': 'FILTER-EMPRESA',
            'name': 'Empresas',
            'filterType': 'filter_select',
            'type': 'NATIVE_FILTER',
            'targets': [{{'datasetId': {kpi_ds}, 'column': {{'name': 'empresa'}}}}],
            'controlValues': {{'multiSelect': True, 'enableEmptyFilter': False, 'sortAscending': True}},
            'scope': {{'rootPath': ['ROOT_ID'], 'excluded': []}},
        }},
        {{
            'id': 'FILTER-DEPT',
            'name': 'Departamentos',
            'filterType': 'filter_select',
            'type': 'NATIVE_FILTER',
            'targets': [{{'datasetId': {detail_ds}, 'column': {{'name': 'department_code'}}}}],
            'controlValues': {{'multiSelect': True, 'enableEmptyFilter': False, 'sortAscending': True}},
            'scope': {{'rootPath': ['ROOT_ID'], 'excluded': []}},
        }},
        {{
            'id': 'FILTER-TIPO',
            'name': 'Tipo P/R',
            'filterType': 'filter_select',
            'type': 'NATIVE_FILTER',
            'targets': [{{'datasetId': {evo_ds}, 'column': {{'name': 'tipo'}}}}],
            'controlValues': {{'multiSelect': False, 'enableEmptyFilter': False}},
            'scope': {{'rootPath': ['ROOT_ID'], 'excluded': []}},
        }},
    ]
    dash.json_metadata = json.dumps(jm)
    dash.css = {dashboard_css!r}
    db.session.commit()
    print('Dashboard config persistida')
"""
    subprocess.run(["docker", "exec", "superset", "python", "-c", code], check=True)


def build_layout(charts: list[dict[str, Any]]) -> dict[str, Any]:
    position: dict[str, Any] = {
        "DASHBOARD_VERSION": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID": {
            "type": "GRID",
            "id": "GRID_ID",
            "children": [
                "ROW-HDR-OBJ", "ROW-OBJ",
                "ROW-HDR-PLAN", "ROW-PLAN",
                "ROW-TABLES", "ROW-CHARTS",
            ],
            "parents": ["ROOT_ID"],
        },
        "ROW-HDR-OBJ": {
            "type": "ROW", "id": "ROW-HDR-OBJ", "children": ["HEADER-OBJ"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-HDR-PLAN": {
            "type": "ROW", "id": "ROW-HDR-PLAN", "children": ["HEADER-PLAN"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "HEADER-OBJ": {
            "type": "MARKDOWN", "id": "HEADER-OBJ", "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW-HDR-OBJ"],
            "meta": {"code": "## Objetivos Anuales", "width": 12, "height": 2},
        },
        "HEADER-PLAN": {
            "type": "MARKDOWN", "id": "HEADER-PLAN", "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW-HDR-PLAN"],
            "meta": {"code": "## Planificación Actual", "width": 12, "height": 2},
        },
        "ROW-OBJ": {
            "type": "ROW", "id": "ROW-OBJ",
            "children": [c["key"] for c in charts if c["section"] == "obj"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-PLAN": {
            "type": "ROW", "id": "ROW-PLAN",
            "children": [c["key"] for c in charts if c["section"] == "plan"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-TABLES": {
            "type": "ROW", "id": "ROW-TABLES",
            "children": [c["key"] for c in charts if c["section"] == "table"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW-CHARTS": {
            "type": "ROW", "id": "ROW-CHARTS",
            "children": [c["key"] for c in charts if c["section"] == "chart"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
    }
    # Ancho en columnas de rejilla (12 = fila completa). Se ajusta al contenido:
    #  - Euros (Facturación, Beneficio): mas ancho (3) para "7.748.763 €"
    #  - Porcentajes (Margen, Crecimiento): mas estrecho (2)
    sizes = {"obj": (2, 14), "plan": (2, 14), "table": (6, 40), "chart": (6, 40)}
    euro_metrics = {"Facturación", "Beneficio"}
    for c in charts:
        w, h = sizes[c["section"]]
        row = {"obj": "ROW-OBJ", "plan": "ROW-PLAN", "table": "ROW-TABLES", "chart": "ROW-CHARTS"}[c["section"]]
        # Titulo mostrado: solo la metrica (Facturación, Margen, Crecimiento, Beneficio)
        # sin el prefijo "Obj ·" / "Plan ·"; la cabecera de seccion ya da el contexto.
        display_name = c["name"].split("· ")[-1]
        if c["section"] in ("obj", "plan"):
            w = 3 if display_name in euro_metrics else 2
        position[c["key"]] = {
            "type": "CHART", "id": c["key"], "children": [],
            "parents": ["ROOT_ID", "GRID_ID", row],
            "meta": {
                "width": w, "height": h,
                "chartId": c["id"], "uuid": c.get("uuid", ""),
                "sliceName": display_name,
                "sliceNameOverride": display_name,
            },
        }
    return position


def main() -> int:
    print("==> 1/4 Aplicando vistas BI en PostgreSQL...")
    apply_bi_views()

    client = SupersetClient()
    client.login()
    print("Login Superset OK")

    print("==> 2/4 Creando datasets...")
    db_id = client.ensure_database()
    dataset_ids = {name: client.ensure_dataset(db_id, name) for name in DATASETS}
    kpi_ds = dataset_ids["bi_v_kpi_anual_empresa"]
    evo_ds = dataset_ids["bi_v_evolucion_mensual"]
    prob_ds = dataset_ids["bi_v_facturacion_probabilidad"]

    print("==> 3/4 Creando charts...")
    existing = {c["slice_name"]: c["id"] for c in client.list_charts()}
    stale_names = set(existing) - {
        "Obj · Facturación", "Obj · Margen", "Obj · Crecimiento", "Obj · Beneficio",
        "Plan · Facturación", "Plan · Margen", "Plan · Crecimiento", "Plan · Beneficio",
        "Resumen mensual", "Evolución mensual", "Margen acumulado", "Facturación por Probabilidad",
        "Facturación", "Margen", "Crecimiento", "Beneficio",
    }
    for name in stale_names:
        if name.startswith(("Obj", "Plan")) or "Planificación" in name:
            client.delete_chart(existing[name])

    chart_specs: list[tuple[str, str, int, str, dict[str, Any]]] = [
        ("Obj · Facturación", "obj", kpi_ds, "big_number_total",
         big_number_params(metric_sum("obj_facturacion", "Facturación"), ",.0f", currency=True)),
        ("Obj · Margen", "obj", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql("SUM(obj_beneficio)/NULLIF(SUM(obj_facturacion),0)*100", "Margen"), ".2f")),
        ("Obj · Crecimiento", "obj", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql(
                 "(SUM(obj_facturacion)-SUM(facturacion_real_anterior))"
                 "/NULLIF(SUM(facturacion_real_anterior),0)*100",
                 "Crecimiento"),
             ".2f")),
        ("Obj · Beneficio", "obj", kpi_ds, "big_number_total",
         big_number_params(metric_sum("obj_beneficio", "Beneficio"), ",.0f", currency=True)),
        ("Plan · Facturación", "plan", kpi_ds, "big_number_total",
         big_number_params(metric_sum("plan_facturacion", "Facturación"), ",.0f", currency=True)),
        ("Plan · Margen", "plan", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql("SUM(plan_beneficio)/NULLIF(SUM(plan_facturacion),0)*100", "Margen"), ".2f")),
        ("Plan · Crecimiento", "plan", kpi_ds, "big_number_total",
         big_number_params(
             metric_sql(
                 "(SUM(plan_facturacion)-SUM(facturacion_real_anterior))"
                 "/NULLIF(SUM(facturacion_real_anterior),0)*100",
                 "Crecimiento"),
             ".2f")),
        ("Plan · Beneficio", "plan", kpi_ds, "big_number_total",
         big_number_params(metric_sum("plan_beneficio", "Beneficio"), ",.0f", currency=True)),
        ("Resumen mensual", "table", evo_ds, "table",
         {"all_columns": ["ano_mes", "facturacion", "coste", "beneficio", "margen_pct"],
          "order_by_cols": ['["ano_mes", true]']}),
        ("Evolución mensual", "chart", evo_ds, "echarts_timeseries_line",
         {"x_axis": "ano_mes", "metrics": [metric_sum("facturacion", "Facturación")],
          "groupby": [], "row_limit": 1000}),
        ("Margen acumulado", "chart", evo_ds, "echarts_timeseries_line",
         {"x_axis": "ano_mes",
          "metrics": [metric_sql("AVG(margen_pct)", "Margen %")],
          "row_limit": 1000}),
        ("Facturación por Probabilidad", "chart", prob_ds, "echarts_timeseries_bar",
         {"x_axis": "probabilidad", "metrics": [metric_sum("facturacion", "Facturación")],
          "row_limit": 100}),
    ]

    charts: list[dict[str, Any]] = []
    for idx, (name, section, ds_id, viz, params) in enumerate(chart_specs, start=1):
        cid = client.upsert_chart(
            name=name, dataset_id=ds_id, viz_type=viz, params=params,
            existing_by_name=existing,
        )
        charts.append({"key": f"CHART-{idx}", "id": cid, "name": name, "section": section})
        existing[name] = cid

    uuids = get_chart_uuids()
    for c in charts:
        c["uuid"] = uuids.get(c["id"], "")

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
    persist_dashboard_config(dash_id, dataset_ids, [c["id"] for c in charts])

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
