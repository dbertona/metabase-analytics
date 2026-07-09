#!/usr/bin/env python3
"""
Configura el dashboard 'Planificación PS Analytics' en Metabase vía API.

Uso:
  export MB_EMAIL="dbertona@powersolution.es"
  export MB_PASSWORD="tu-contraseña"
  python3 scripts/setup-dashboard-planificacion.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

MB_URL = os.environ.get("MB_URL", "http://localhost:3000")
MB_EMAIL = os.environ.get("MB_EMAIL", "")
MB_PASSWORD = os.environ.get("MB_PASSWORD", "")
DB_HOST = os.environ.get("DB_HOST", "supabase-db")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "postgres")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "SuperSecurePassword2025")
DB_LABEL = os.environ.get("DB_LABEL", "PS Analytics")
DASHBOARD_NAME = "Planificación PS Analytics"

TEMPLATE_TAGS = {
    "anio": {
        "id": "anio",
        "name": "anio",
        "display-name": "Año",
        "type": "number",
        "default": "2026",
        "required": True,
    },
    "empresa": {
        "id": "empresa",
        "name": "empresa",
        "display-name": "Empresa",
        "type": "text",
        "required": False,
    },
    "departamento": {
        "id": "departamento",
        "name": "departamento",
        "display-name": "Departamento",
        "type": "text",
        "required": False,
    },
    "tipo_pr": {
        "id": "tipo_pr",
        "name": "tipo_pr",
        "display-name": "Tipo (P/R)",
        "type": "text",
        "default": "P",
        "required": True,
    },
}

FILTER_WHERE = """
WHERE k.year = {{anio}}
  [[AND k.company_name = {{empresa}}]]
  [[AND k.department_code IN ({{departamento}})]]
"""

CARDS = [
    {
        "name": "Obj - Facturación",
        "display": "scalar",
        "sql": f"SELECT ROUND(SUM(k.facturacion)) AS valor FROM mb_v_dashboard_kpi k {FILTER_WHERE} AND k.seccion = 'Objetivos Anuales'",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"prefix": "", "suffix": " €", "number_style": "decimal"}}},
    },
    {
        "name": "Obj - Margen %",
        "display": "scalar",
        "sql": f"SELECT ROUND((SUM(k.facturacion)-SUM(k.coste))/NULLIF(SUM(k.facturacion),0)*100, 2) AS valor FROM mb_v_dashboard_kpi k {FILTER_WHERE} AND k.seccion = 'Objetivos Anuales'",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " %"}}},
    },
    {
        "name": "Obj - Crecimiento %",
        "display": "scalar",
        "sql": f"""
WITH agg AS (
  SELECT SUM(k.facturacion) AS fact
  FROM mb_v_dashboard_kpi k
  {FILTER_WHERE} AND k.seccion = 'Objetivos Anuales'
),
real_ant AS (
  SELECT SUM(rae.facturacion_real_anterior) AS fact_ant
  FROM mb_v_real_anio_anterior_empresa rae
  WHERE rae.year = {{{{anio}}}}
    [[AND rae.company_name = {{{{empresa}}}}]]
)
SELECT ROUND((agg.fact - real_ant.fact_ant) / NULLIF(real_ant.fact_ant, 0) * 100, 2) AS valor
FROM agg, real_ant
""",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " %"}}},
    },
    {
        "name": "Obj - Beneficio",
        "display": "scalar",
        "sql": f"SELECT ROUND(SUM(k.beneficio)) AS valor FROM mb_v_dashboard_kpi k {FILTER_WHERE} AND k.seccion = 'Objetivos Anuales'",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " €"}}},
    },
    {
        "name": "Plan - Facturación",
        "display": "scalar",
        "sql": f"SELECT ROUND(SUM(k.facturacion)) AS valor FROM mb_v_dashboard_kpi k {FILTER_WHERE} AND k.seccion = 'Planificación Actual'",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " €"}}},
    },
    {
        "name": "Plan - Margen %",
        "display": "scalar",
        "sql": f"SELECT ROUND((SUM(k.facturacion)-SUM(k.coste))/NULLIF(SUM(k.facturacion),0)*100, 2) AS valor FROM mb_v_dashboard_kpi k {FILTER_WHERE} AND k.seccion = 'Planificación Actual'",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " %"}}},
    },
    {
        "name": "Plan - Crecimiento %",
        "display": "scalar",
        "sql": f"""
WITH agg AS (
  SELECT SUM(k.facturacion) AS fact
  FROM mb_v_dashboard_kpi k
  {FILTER_WHERE} AND k.seccion = 'Planificación Actual'
),
real_ant AS (
  SELECT SUM(rae.facturacion_real_anterior) AS fact_ant
  FROM mb_v_real_anio_anterior_empresa rae
  WHERE rae.year = {{{{anio}}}}
    [[AND rae.company_name = {{{{empresa}}}}]]
)
SELECT ROUND((agg.fact - real_ant.fact_ant) / NULLIF(real_ant.fact_ant, 0) * 100, 2) AS valor
FROM agg, real_ant
""",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " %"}}},
    },
    {
        "name": "Plan - Beneficio",
        "display": "scalar",
        "sql": f"SELECT ROUND(SUM(k.beneficio)) AS valor FROM mb_v_dashboard_kpi k {FILTER_WHERE} AND k.seccion = 'Planificación Actual'",
        "viz": {"scalar.field": "valor", "column_settings": {'["name","valor"]': {"suffix": " €"}}},
    },
    {
        "name": "Resumen por sección",
        "display": "table",
        "sql": """
SELECT
  k.seccion,
  ROUND(SUM(k.facturacion)) AS facturacion,
  ROUND(SUM(k.coste)) AS coste,
  ROUND(SUM(k.beneficio)) AS beneficio,
  ROUND((SUM(k.facturacion)-SUM(k.coste))/NULLIF(SUM(k.facturacion),0)*100, 2) AS margen_pct
FROM mb_v_dashboard_kpi k
WHERE k.year = {{anio}}
  [[AND k.company_name = {{empresa}}]]
  [[AND k.department_code IN ({{departamento}})]]
GROUP BY k.seccion
ORDER BY k.seccion
""",
        "viz": {},
        "tags": ["anio", "empresa", "departamento"],
    },
    {
        "name": "Evolución facturación mensual",
        "display": "line",
        "sql": """
SELECT e.month AS mes, SUM(e.facturacion) AS facturacion
FROM mb_v_evolucion_mensual e
WHERE e.year = {{anio}} AND e.tipo = {{tipo_pr}}
  [[AND e.company_name = {{empresa}}]]
  [[AND e.department_code IN ({{departamento}})]]
GROUP BY e.month
ORDER BY e.month
""",
        "viz": {"graph.dimensions": ["mes"], "graph.metrics": ["facturacion"]},
        "tags": ["anio", "tipo_pr", "empresa", "departamento"],
    },
    {
        "name": "Evolución margen mensual",
        "display": "line",
        "sql": """
SELECT e.month AS mes,
  ROUND((SUM(e.facturacion)-SUM(e.coste))/NULLIF(SUM(e.facturacion),0)*100, 2) AS margen
FROM mb_v_evolucion_mensual e
WHERE e.year = {{anio}} AND e.tipo = {{tipo_pr}}
  [[AND e.company_name = {{empresa}}]]
  [[AND e.department_code IN ({{departamento}})]]
GROUP BY e.month
ORDER BY e.month
""",
        "viz": {"graph.dimensions": ["mes"], "graph.metrics": ["margen"]},
        "tags": ["anio", "tipo_pr", "empresa", "departamento"],
    },
]

DASHBOARD_LAYOUT = [
    (0, 0, 6, 3), (0, 6, 6, 3), (0, 12, 6, 3), (0, 18, 6, 3),
    (3, 0, 6, 3), (3, 6, 6, 3), (3, 12, 6, 3), (3, 18, 6, 3),
    (6, 0, 8, 6), (6, 8, 8, 6), (6, 16, 8, 6),
]


class MetabaseClient:
    def __init__(self, base_url: str, session_id: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.session_id = session_id

    def request(self, method: str, path: str, data: dict | None = None) -> dict:
        url = f"{self.base_url}{path}"
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(
            url,
            data=body,
            method=method,
            headers={
                "Content-Type": "application/json",
                "X-Metabase-Session": self.session_id,
            },
        )
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode()
            raise RuntimeError(f"{method} {path} → {exc.code}: {detail}") from exc


def login() -> str:
    payload = json.dumps({"username": MB_EMAIL, "password": MB_PASSWORD}).encode()
    req = urllib.request.Request(
        f"{MB_URL}/api/session",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())["id"]


def get_or_create_database(client: MetabaseClient) -> int:
    dbs = client.request("GET", "/api/database")["data"]
    for db in dbs:
        if db["name"] == DB_LABEL:
            print(f"✅ Conexión existente: {DB_LABEL} (id={db['id']})")
            return db["id"]

    print(f"🔧 Creando conexión {DB_LABEL}...")
    created = client.request(
        "POST",
        "/api/database",
        {
            "engine": "postgres",
            "name": DB_LABEL,
            "details": {
                "host": DB_HOST,
                "port": DB_PORT,
                "dbname": DB_NAME,
                "user": DB_USER,
                "password": DB_PASS,
                "ssl": False,
                "tunnel-enabled": False,
            },
            "auto_sync": True,
            "is_full_sync": True,
        },
    )
    db_id = created["id"]
    client.request("POST", f"/api/database/{db_id}/sync_schema", {})
    time.sleep(5)
    print(f"✅ Base de datos creada (id={db_id})")
    return db_id


def tags_for_card(tag_names: list[str] | None) -> dict:
    names = tag_names or ["anio", "empresa", "departamento"]
    return {name: TEMPLATE_TAGS[name] for name in names}


def create_card(client: MetabaseClient, db_id: int, spec: dict) -> int:
    card = client.request(
        "POST",
        "/api/card",
        {
            "name": spec["name"],
            "display": spec["display"],
            "visualization_settings": spec.get("viz", {}),
            "dataset_query": {
                "type": "native",
                "native": {
                    "query": spec["sql"].strip(),
                    "template-tags": tags_for_card(spec.get("tags")),
                },
                "database": db_id,
            },
        },
    )
    print(f"  📊 {spec['name']} → id={card['id']}")
    return card["id"]


def main() -> int:
    if not MB_EMAIL or not MB_PASSWORD:
        print("❌ Define MB_EMAIL y MB_PASSWORD", file=sys.stderr)
        return 1

    print(f"🔐 Autenticando en {MB_URL}...")
    session = login()
    client = MetabaseClient(MB_URL, session)

    db_id = get_or_create_database(client)

    print("📈 Creando preguntas...")
    card_ids: list[int] = []
    for spec in CARDS:
        card_ids.append(create_card(client, db_id, spec))

    print(f"🎛️  Creando dashboard '{DASHBOARD_NAME}'...")
    dashboard = client.request(
        "POST",
        "/api/dashboard",
        {
            "name": DASHBOARD_NAME,
            "description": "Réplica del dashboard Power BI - Objetivos y Planificación",
        },
    )
    dashboard_id = dashboard["id"]

    dashcards = []
    for i, (card_id, (row, col, sx, sy)) in enumerate(zip(card_ids, DASHBOARD_LAYOUT)):
        dashcards.append(
            {
                "id": -(i + 1),
                "card_id": card_id,
                "row": row,
                "col": col,
                "size_x": sx,
                "size_y": sy,
                "series": [],
                "visualization_settings": {},
                "parameter_mappings": [],
            }
        )

    client.request(
        "PUT",
        f"/api/dashboard/{dashboard_id}",
        {
            "name": DASHBOARD_NAME,
            "description": dashboard.get("description"),
            "parameters": dashboard.get("parameters", []),
            "dashcards": dashcards,
            "tabs": dashboard.get("tabs", []),
        },
    )

    print()
    print("═" * 60)
    print(f"✅ Dashboard listo: {MB_URL}/dashboard/{dashboard_id}")
    print()
    print("Filtros del dashboard (añadir en Metabase UI si no se vinculan solos):")
    print("  • Año → parámetro 'anio' (default 2026)")
    print("  • Empresa → parámetro 'empresa'")
    print("  • Departamento → parámetro 'departamento'")
    print("  • P/R → parámetro 'tipo_pr' (P=Planificación, R=Real)")
    print("═" * 60)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
