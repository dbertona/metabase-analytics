#!/usr/bin/env python3
"""
Carga Plan MdO de meses cerrados desde BC jobPlanningUnified → Analytics.

Filtra: lineTypeEnum=Resource, planningType=PlanningLine, closingMonthCode relleno.
Agrega por (job, closingMonthCode, nr) usando probabilizedCostLCY.

Auth: cache MSAL ~/.bc_odata_mcp (mismo CLIENT_ID que MCP / copy-job-planning-unified).

Ejemplos:
  /tmp/ps-sync-venv/bin/python scripts/sync_historico_mano_obra.py \\
    --company "Power Solution Iberia" --since 2025.01 --until 2026.12

  ANALYTICS_DSN=postgresql://... python scripts/sync_historico_mano_obra.py --all-companies
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any

import msal
import psycopg2
import psycopg2.extras
import requests

TENANT_ID = "a18dc497-a8b8-4740-b723-65362ab7a3fb"
CLIENT_ID = "3dda69c6-0e2b-4f44-b765-f8bddec066e3"
SCOPE = ["https://api.businesscentral.dynamics.com/.default"]
BC_BASE = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT_ID}"
CACHE_PATH = Path.home() / ".bc_odata_mcp" / "token_cache.bin"
DEFAULT_API = "api/Power_Solution/PS_API/v2.0"
ENTITY = "jobPlanningUnified"
DEFAULT_DSN = os.environ.get(
    "ANALYTICS_DSN",
    "postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/postgres",
)

# BC company name → Analytics company_name (displayName / bc_job)
COMPANY_TO_ANALYTICS = {
    "Power Solution Iberia": "Power Solution Iberia SL",
    "Power Lab Iberia": "PS LAB CONSULTING SL",
}

CLOSING_RE = re.compile(r"^(\d{4})\.(\d{1,2})$")


def get_token() -> str:
    cache = msal.SerializableTokenCache()
    if CACHE_PATH.exists():
        cache.deserialize(CACHE_PATH.read_text())
    app = msal.PublicClientApplication(
        CLIENT_ID,
        authority=f"https://login.microsoftonline.com/{TENANT_ID}",
        token_cache=cache,
    )
    result = None
    accounts = app.get_accounts()
    if accounts:
        result = app.acquire_token_silent(SCOPE, account=accounts[0])
    if not result or "access_token" not in result:
        flow = app.initiate_device_flow(scopes=SCOPE)
        if "user_code" not in flow:
            raise RuntimeError(f"Device flow error: {flow}")
        print(flow["message"], file=sys.stderr, flush=True)
        result = app.acquire_token_by_device_flow(flow)
    if cache.has_state_changed:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(cache.serialize())
    if "access_token" not in result:
        raise RuntimeError(result.get("error_description", result))
    return result["access_token"]


def parse_closing(code: str) -> tuple[int, int] | None:
    m = CLOSING_RE.match((code or "").strip())
    if not m:
        return None
    year, month = int(m.group(1)), int(m.group(2))
    if month < 1 or month > 12:
        return None
    return year, month


def month_codes(since: str, until: str) -> list[str]:
    sy, sm = parse_closing(since) or (0, 0)
    uy, um = parse_closing(until) or (0, 0)
    if not sy or not uy:
        raise SystemExit(f"Invalid --since/--until (use YYYY.MM): {since} {until}")
    out: list[str] = []
    y, m = sy, sm
    while (y, m) <= (uy, um):
        out.append(f"{y}.{m:02d}")
        m += 1
        if m > 12:
            m = 1
            y += 1
    return out


def company_id(session: requests.Session, env: str, company: str) -> str:
    r = session.get(f"{BC_BASE}/{env}/api/v2.0/companies", timeout=60)
    r.raise_for_status()
    companies = r.json().get("value", [])
    cid = next((c["id"] for c in companies if c["name"] == company), None)
    if not cid:
        raise RuntimeError(f"Company '{company}' not in {env}")
    return cid


def fetch_month(
    session: requests.Session, url: str, closing: str
) -> list[dict[str, Any]]:
    """Paginación por $skip (BC a veces no devuelve @odata.nextLink con $filter)."""
    rows: list[dict[str, Any]] = []
    filt = (
        f"closingMonthCode eq '{closing}' "
        f"and lineTypeEnum eq 'Resource' "
        f"and planningType eq 'PlanningLine'"
    )
    select = (
        "jobNo,closingMonthCode,planningDate,lineTypeEnum,no,quantity,"
        "probabilizedCostLCY,probability,planningType"
    )
    page_size = 1000
    skip = 0
    while True:
        r = session.get(
            url,
            params={
                "$filter": filt,
                "$select": select,
                "$top": str(page_size),
                "$skip": str(skip),
            },
            timeout=180,
            headers={"Prefer": f"odata.maxpagesize={page_size}"},
        )
        r.raise_for_status()
        chunk = r.json().get("value") or []
        rows.extend(chunk)
        if len(chunk) < page_size:
            break
        skip += page_size
        if skip > 500_000:
            raise RuntimeError(f"Pagination safety stop at skip={skip} for {closing}")
    return rows


def planning_year_month(planning_date: Any) -> tuple[int, int] | None:
    """OData date → (year, month). Solo el mes de planningDate (no el snapshot entero)."""
    if not planning_date:
        return None
    s = str(planning_date).strip()
    if len(s) < 7:
        return None
    try:
        return int(s[0:4]), int(s[5:7])
    except ValueError:
        return None


def aggregate(rows: list[dict[str, Any]]) -> dict[tuple[str, str, str], dict[str, Any]]:
    """Agrega coste Resource del snapshot, solo líneas con planningDate en el mes de cierre."""
    acc: dict[tuple[str, str, str], dict[str, Any]] = {}
    for row in rows:
        job = (row.get("jobNo") or "").strip()
        closing = (row.get("closingMonthCode") or "").strip()
        nr = (row.get("no") or "").strip()
        if not job or not closing:
            continue
        closing_ym = parse_closing(closing)
        plan_ym = planning_year_month(row.get("planningDate"))
        if not closing_ym or not plan_ym:
            continue
        # Evita inflar el mes cerrado con todo el plan futuro del snapshot.
        if plan_ym != closing_ym:
            continue
        year, month = plan_ym
        key = (job, closing, nr)
        slot = acc.get(key)
        if not slot:
            slot = {
                "job_no": job,
                "closing_month_code": closing,
                "year": year,
                "month": month,
                "nr": nr,
                "cost": 0.0,
                "quantity": 0.0,
                "probability": None,
            }
            acc[key] = slot
        slot["cost"] += float(row.get("probabilizedCostLCY") or 0)
        slot["quantity"] += float(row.get("quantity") or 0)
        if slot["probability"] is None and row.get("probability") is not None:
            try:
                slot["probability"] = float(row["probability"])
            except (TypeError, ValueError):
                pass
    return acc


def upsert_month(
    conn, company_analytics: str, closing: str, agg: dict[tuple, dict[str, Any]]
) -> int:
    ym = parse_closing(closing)
    assert ym
    year, month = ym
    with conn.cursor() as cur:
        cur.execute(
            """
            DELETE FROM public.bc_historico_mano_obra_mes
            WHERE company_name = %s AND year = %s AND month = %s
              AND closing_month_code = %s
            """,
            (company_analytics, year, month, closing),
        )
        if not agg:
            return 0
        rows = [
            (
                company_analytics,
                v["job_no"],
                v["year"],
                v["month"],
                v["closing_month_code"],
                v["nr"],
                "Resource",
                v["cost"],
                v["quantity"],
                v["probability"],
            )
            for v in agg.values()
            if abs(v["cost"]) > 0.0001 or abs(v["quantity"]) > 0.0001
        ]
        if not rows:
            return 0
        psycopg2.extras.execute_values(
            cur,
            """
            INSERT INTO public.bc_historico_mano_obra_mes
              (company_name, job_no, year, month, closing_month_code,
               nr, type_line, cost, quantity, probability, updated_at)
            VALUES %s
            """,
            rows,
            template="(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW())",
            page_size=500,
        )
        return len(rows)


def ensure_table(conn) -> None:
    sql_path = (
        Path(__file__).resolve().parent.parent
        / "sql"
        / "tables"
        / "bc_historico_mano_obra_mes.sql"
    )
    with conn.cursor() as cur:
        cur.execute(sql_path.read_text())
    conn.commit()


def sync_company(
    session: requests.Session,
    conn,
    env: str,
    company_bc: str,
    codes: list[str],
) -> None:
    company_analytics = COMPANY_TO_ANALYTICS.get(company_bc, company_bc)
    cid = company_id(session, env, company_bc)
    url = f"{BC_BASE}/{env}/{DEFAULT_API}/companies({cid})/{ENTITY}"
    total = 0
    for closing in codes:
        rows = fetch_month(session, url, closing)
        agg = aggregate(rows)
        n = upsert_month(conn, company_analytics, closing, agg)
        conn.commit()
        total += n
        print(
            f"  {company_analytics} {closing}: bc_rows={len(rows)} upsert={n}",
            flush=True,
        )
    print(f"✅ {company_analytics}: {total} filas escritas", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--env", default="Production")
    ap.add_argument("--company", action="append", dest="companies", default=None)
    ap.add_argument("--all-companies", action="store_true")
    ap.add_argument("--since", default="2024.01")
    ap.add_argument("--until", default="2026.12")
    ap.add_argument("--dsn", default=DEFAULT_DSN)
    args = ap.parse_args()

    if args.all_companies:
        companies = list(COMPANY_TO_ANALYTICS.keys())
    else:
        companies = args.companies or ["Power Solution Iberia"]

    codes = month_codes(args.since, args.until)
    token = get_token()
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {token}"
    session.headers["Accept"] = "application/json"

    conn = psycopg2.connect(args.dsn)
    try:
        ensure_table(conn)
        for company in companies:
            print(f"→ {company} ({args.env}) months={len(codes)}", flush=True)
            sync_company(session, conn, args.env, company, codes)
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
