#!/usr/bin/env python3
"""Trae el estado actual del dashboard Resumen desde la UI de Superset (prod).

Antes de regenerar con setup-superset-planificacion.py, ejecuta este script (o
déjalo que lo invoque el setup) para:

  1. Guardar snapshot de dashboard + charts en exports/superset-dashboard/latest/
  2. Comparar con el snapshot anterior (si existe) y listar divergencias

Así los cambios hechos a mano en la UI no se pierden sin aviso.

Uso:
  SUPERSET_URL=http://192.168.36.100:8088 python3 scripts/pull-superset-dashboard.py
  python3 scripts/pull-superset-dashboard.py --strict   # exit 1 si hay diff vs snapshot previo

Variables:
  SUPERSET_URL, SUPERSET_USER, SUPERSET_PASSWORD
  SKIP_SUPERSET_PULL=1  — el setup no llama a este script
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.cookiejar import CookieJar
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EXPORT_ROOT = ROOT / "exports" / "superset-dashboard"
LATEST_DIR = EXPORT_ROOT / "latest"
PREV_DIR = EXPORT_ROOT / "previous"

SUPERSET_URL = os.environ.get("SUPERSET_URL", "http://localhost:8088").rstrip("/")
SUPERSET_USER = os.environ.get("SUPERSET_USER", "admin")
SUPERSET_PASSWORD = os.environ.get("SUPERSET_PASSWORD", "PsSuperset#2026xK9!")
DASHBOARD_SLUG = os.environ.get("DASHBOARD_SLUG", "planificacion-ps-analytics")
DASHBOARD_TITLE = os.environ.get(
    "DASHBOARD_TITLE", "Seguimiento Económico — Resumen"
)

# Charts gestionados por setup-superset-planificacion.py
MANAGED_CHART_NAMES = {
    "Obj · Facturación",
    "Obj · Margen",
    "Obj · Crecimiento",
    "Obj · Beneficio",
    "Plan · Facturación",
    "Plan · Margen",
    "Plan · Crecimiento",
    "Plan · Beneficio",
    "Resumen mensual",
    "Evolución mensual",
    "Margen acumulado",
    "Facturación por Probabilidad",
}


class SupersetClient:
    def __init__(self) -> None:
        self.token: str | None = None
        self.csrf: str | None = None
        self.jar = CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar)
        )

    def _request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        auth: bool = True,
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
            raise RuntimeError(
                f"{method} {path} -> {exc.code}: {exc.read().decode()}"
            ) from exc

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


def _slugify(name: str) -> str:
    s = re.sub(r"[^\w\-]+", "_", name, flags=re.UNICODE).strip("_")
    return s[:80] or "chart"


def _parse_params(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"_raw": raw}
    return {}


def _chart_fingerprint(chart: dict[str, Any]) -> dict[str, Any]:
    """Campos estables para diff (ignora timestamps / owners)."""
    params = _parse_params(chart.get("params"))
    # Solo claves que suelen cambiar en UI
    keep_param_keys = (
        "metrics",
        "metric",
        "groupby",
        "adhoc_filters",
        "x_axis",
        "orientation",
        "show_cell_bars",
        "show_value",
        "show_bar_value",
        "y_axis_format",
        "column_config",
        "row_limit",
        "order_by_cols",
        "seriesType",
    )
    slim_params = {k: params[k] for k in keep_param_keys if k in params}
    return {
        "id": chart.get("id"),
        "slice_name": chart.get("slice_name"),
        "viz_type": chart.get("viz_type"),
        "datasource_id": chart.get("datasource_id"),
        "params": slim_params,
    }


def _dashboard_fingerprint(dash: dict[str, Any]) -> dict[str, Any]:
    pos_raw = dash.get("position_json") or "{}"
    try:
        pos = json.loads(pos_raw) if isinstance(pos_raw, str) else (pos_raw or {})
    except json.JSONDecodeError:
        pos = {}
    charts_meta = []
    for key, node in sorted(pos.items()):
        if not isinstance(node, dict) or node.get("type") != "CHART":
            continue
        meta = node.get("meta") or {}
        charts_meta.append(
            {
                "key": key,
                "chartId": meta.get("chartId"),
                "sliceName": meta.get("sliceName") or meta.get("sliceNameOverride"),
                "width": meta.get("width"),
                "height": meta.get("height"),
            }
        )
    meta_raw = dash.get("json_metadata") or "{}"
    try:
        jm = json.loads(meta_raw) if isinstance(meta_raw, str) else (meta_raw or {})
    except json.JSONDecodeError:
        jm = {}
    filters = [
        {"id": f.get("id"), "name": f.get("name")}
        for f in (jm.get("native_filter_configuration") or [])
        if isinstance(f, dict)
    ]
    return {
        "id": dash.get("id"),
        "dashboard_title": dash.get("dashboard_title"),
        "slug": dash.get("slug"),
        "published": dash.get("published"),
        "charts_layout": charts_meta,
        "native_filters": filters,
    }


def find_dashboard(client: SupersetClient) -> dict[str, Any]:
    for col, value in (("slug", DASHBOARD_SLUG), ("dashboard_title", DASHBOARD_TITLE)):
        q = {"filters": [{"col": col, "opr": "eq", "value": value}]}
        res = client._request(
            "GET", f"/api/v1/dashboard/?q={urllib.parse.quote(json.dumps(q))}"
        )
        items = res.get("result") or []
        if items:
            dash_id = items[0]["id"]
            detail = client._request("GET", f"/api/v1/dashboard/{dash_id}")
            return detail.get("result") or items[0]
    raise RuntimeError(
        f"Dashboard no encontrado (slug={DASHBOARD_SLUG!r} title={DASHBOARD_TITLE!r})"
    )


def list_charts(client: SupersetClient) -> list[dict[str, Any]]:
    res = client._request(
        "GET",
        "/api/v1/chart/?q="
        + urllib.parse.quote(json.dumps({"page_size": 200})),
    )
    return res.get("result") or []


def pull_snapshot(client: SupersetClient) -> tuple[Path, dict[str, Any]]:
    dash = find_dashboard(client)
    charts = list_charts(client)
    managed = [
        c
        for c in charts
        if c.get("slice_name") in MANAGED_CHART_NAMES
        or any(
            str(d.get("id") if isinstance(d, dict) else d) == str(dash.get("id"))
            for d in (c.get("dashboards") or [])
        )
    ]
    # Prefer managed names; if API omits dashboards relation, fall back to names only
    if not managed:
        managed = [c for c in charts if c.get("slice_name") in MANAGED_CHART_NAMES]

    # Full chart details (params completos)
    detailed: list[dict[str, Any]] = []
    for c in managed:
        cid = c["id"]
        detail = client._request("GET", f"/api/v1/chart/{cid}")
        detailed.append(detail.get("result") or c)

    EXPORT_ROOT.mkdir(parents=True, exist_ok=True)
    if LATEST_DIR.exists():
        if PREV_DIR.exists():
            shutil.rmtree(PREV_DIR)
        LATEST_DIR.rename(PREV_DIR)

    LATEST_DIR.mkdir(parents=True, exist_ok=True)
    charts_dir = LATEST_DIR / "charts"
    charts_dir.mkdir(exist_ok=True)

    fingerprint = {
        "pulled_at": datetime.now(timezone.utc).isoformat(),
        "superset_url": SUPERSET_URL,
        "dashboard": _dashboard_fingerprint(dash),
        "charts": [_chart_fingerprint(c) for c in sorted(detailed, key=lambda x: x.get("id") or 0)],
    }

    (LATEST_DIR / "dashboard.json").write_text(
        json.dumps(dash, indent=2, ensure_ascii=False, default=str) + "\n",
        encoding="utf-8",
    )
    (LATEST_DIR / "fingerprint.json").write_text(
        json.dumps(fingerprint, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    for c in detailed:
        name = _slugify(str(c.get("slice_name") or c.get("id")))
        fname = f"{c.get('id')}_{name}.json"
        (charts_dir / fname).write_text(
            json.dumps(c, indent=2, ensure_ascii=False, default=str) + "\n",
            encoding="utf-8",
        )

    manifest = {
        "pulled_at": fingerprint["pulled_at"],
        "superset_url": SUPERSET_URL,
        "dashboard_id": dash.get("id"),
        "dashboard_title": dash.get("dashboard_title"),
        "slug": dash.get("slug"),
        "chart_files": sorted(p.name for p in charts_dir.glob("*.json")),
        "managed_chart_count": len(detailed),
    }
    (LATEST_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return LATEST_DIR, fingerprint


def diff_fingerprints(
    prev: dict[str, Any], curr: dict[str, Any]
) -> list[str]:
    msgs: list[str] = []
    pd = prev.get("dashboard") or {}
    cd = curr.get("dashboard") or {}
    for key in ("dashboard_title", "slug", "published"):
        if pd.get(key) != cd.get(key):
            msgs.append(f"dashboard.{key}: {pd.get(key)!r} → {cd.get(key)!r}")

    def layout_map(fp: dict[str, Any]) -> dict[str, dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        for item in (fp.get("dashboard") or {}).get("charts_layout") or []:
            name = item.get("sliceName") or str(item.get("chartId"))
            out[str(name)] = item
        return out

    pl, cl = layout_map(prev), layout_map(curr)
    for name in sorted(set(pl) | set(cl)):
        if name not in pl:
            msgs.append(f"layout +chart {name!r}")
        elif name not in cl:
            msgs.append(f"layout -chart {name!r}")
        else:
            for k in ("width", "height", "chartId"):
                if pl[name].get(k) != cl[name].get(k):
                    msgs.append(
                        f"layout {name}.{k}: {pl[name].get(k)!r} → {cl[name].get(k)!r}"
                    )

    def charts_map(fp: dict[str, Any]) -> dict[str, dict[str, Any]]:
        return {
            str(c.get("slice_name")): c
            for c in (fp.get("charts") or [])
            if c.get("slice_name")
        }

    pc, cc = charts_map(prev), charts_map(curr)
    for name in sorted(set(pc) | set(cc)):
        if name not in pc:
            msgs.append(f"chart +{name!r}")
            continue
        if name not in cc:
            msgs.append(f"chart -{name!r}")
            continue
        a, b = pc[name], cc[name]
        if a.get("viz_type") != b.get("viz_type"):
            msgs.append(
                f"chart {name}.viz_type: {a.get('viz_type')!r} → {b.get('viz_type')!r}"
            )
        if a.get("params") != b.get("params"):
            msgs.append(f"chart {name}.params (métricas/filtros/formato) cambiaron en UI")
    return msgs


def compare_with_previous(curr: dict[str, Any]) -> list[str]:
    prev_fp = PREV_DIR / "fingerprint.json"
    if not prev_fp.exists():
        return []
    prev = json.loads(prev_fp.read_text(encoding="utf-8"))
    return diff_fingerprints(prev, curr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 si el snapshot difiere del previous (cambios UI detectados)",
    )
    args = parser.parse_args(argv)

    client = SupersetClient()
    client.login()
    print(f"Login OK → {SUPERSET_URL}")

    out_dir, fingerprint = pull_snapshot(client)
    print(f"Snapshot guardado: {out_dir.relative_to(ROOT)}")
    print(
        f"  dashboard: {fingerprint['dashboard'].get('dashboard_title')} "
        f"(slug={fingerprint['dashboard'].get('slug')})"
    )
    print(f"  charts: {len(fingerprint.get('charts') or [])}")

    diffs = compare_with_previous(fingerprint)
    if not diffs:
        if (PREV_DIR / "fingerprint.json").exists():
            print("Sin divergencias vs snapshot previous.")
        else:
            print("Primer snapshot (no hay previous para comparar).")
        return 0

    print("\n⚠️  Divergencias vs snapshot previous (posible edición en UI):")
    for line in diffs:
        print(f"  - {line}")
    print(
        "\nSi quieres conservar cambios de UI, incorpóralos al script "
        "setup-superset-planificacion.py antes de regenerar."
    )
    print(f"Detalle: {out_dir / 'fingerprint.json'}")
    if args.strict:
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
