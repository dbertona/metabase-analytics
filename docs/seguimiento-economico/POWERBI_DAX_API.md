# Consultas DAX contra Power BI Service — Seguimiento Económico PS

Cómo ejecutar queries DAX directamente contra el dataset publicado en Power BI Service,
sin necesidad de DAX Studio ni acceso a ninguna VM.

---

## Requisitos previos

| Componente | Detalle |
|-----------|---------|
| Python | 3.8+ (disponible en macOS/Linux/Windows) |
| `msal` | Ya instalado en `~/.bc_odata_mcp/venv/` |
| Acceso a internet | Para llamar a `api.powerbi.com` y `login.microsoftonline.com` |
| Cuenta Azure AD | La misma con la que accedes a `app.powerbi.com` (Power Solution) |

---

## Datos de conexión

```python
TENANT_ID  = "a18dc497-a8b8-4740-b723-65362ab7a3fb"
CLIENT_ID  = "ea0616ba-638b-4df5-95b9-636659ae5121"   # Power BI Desktop (app pública Microsoft)
DATASET_ID = "bd3dc81a-3bd3-4699-8fc6-f039c79c1821"   # Seguimiento Económico PS
PBI_SCOPE  = ["https://analysis.windows.net/powerbi/api/.default"]
CACHE_PATH = Path.home() / ".bc_odata_mcp" / "pbi_pbidesktop_cache.bin"
```

> **Por qué `ea0616ba…` y no el Client ID de `cursor-bc-mcp`:**
> La app `cursor-bc-mcp` (`3dda69c6…`) no tiene permiso para `Power BI Service` en su registro
> Azure AD. El Client ID `ea0616ba…` es la app nativa pública de **Power BI Desktop**
> (registrada por Microsoft), que sí tiene los permisos necesarios en cualquier tenant.

---

## Autenticación (primera vez)

La primera vez se usa **device code flow**: el script imprime un código y una URL.
El usuario lo introduce en el navegador y autoriza. El token queda cacheado en disco.

```python
source ~/.bc_odata_mcp/venv/bin/activate
python3 scripts/pbi_dax_query.py "EVALUATE ROW(\"test\", 1)"
# → imprime: To sign in, use a web browser to open https://login.microsoft.com/device
#            and enter the code XXXXXXX to authenticate.
```

A partir de la segunda llamada el token se renueva silenciosamente desde la caché.
Si expira completamente (~90 días de inactividad), se vuelve a pedir el device code.

---

## Función helper reutilizable

```python
#!/usr/bin/env python3
"""
Helper: ejecutar DAX contra Power BI Service — Seguimiento Económico PS
Uso: from pbi_helper import run_dax
"""
import json
import urllib.request
from pathlib import Path

import msal

TENANT_ID  = "a18dc497-a8b8-4740-b723-65362ab7a3fb"
CLIENT_ID  = "ea0616ba-638b-4df5-95b9-636659ae5121"
DATASET_ID = "bd3dc81a-3bd3-4699-8fc6-f039c79c1821"
PBI_SCOPE  = ["https://analysis.windows.net/powerbi/api/.default"]
CACHE_PATH = Path.home() / ".bc_odata_mcp" / "pbi_pbidesktop_cache.bin"


def _get_token() -> str:
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
        result = app.acquire_token_silent(PBI_SCOPE, account=accounts[0])

    if not result:
        import sys
        flow = app.initiate_device_flow(scopes=PBI_SCOPE)
        print(flow["message"], file=sys.stderr, flush=True)
        result = app.acquire_token_by_device_flow(flow)

    if cache.has_state_changed:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(cache.serialize())

    if "access_token" not in result:
        raise RuntimeError(f"PBI auth error: {result.get('error_description', result)}")

    return result["access_token"]


def run_dax(query: str, dataset_id: str = DATASET_ID) -> list[dict]:
    """
    Ejecuta una query DAX y devuelve una lista de filas como dicts.
    Las claves del dict tienen el formato "Tabla[Medida]" o "Tabla[Campo]".

    Ejemplo:
        rows = run_dax("EVALUATE ROW(\\"TotalVenta\\", [TotalVenta])")
        # [{"Facturacion[TotalVenta]": 3695962.45}]
    """
    token = _get_token()
    url = f"https://api.powerbi.com/v1.0/myorg/datasets/{dataset_id}/executeQueries"
    body = json.dumps({
        "queries": [{"query": query}],
        "serializerSettings": {"includeNulls": True},
    }).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as r:
        resp = json.loads(r.read())

    return resp["results"][0]["tables"][0].get("rows", [])
```

---

## Ejemplos de queries DAX

### Facturación P+R por empresa y año

```dax
EVALUATE
SUMMARIZECOLUMNS(
    Facturacion[Empresa],
    Facturacion[year],
    "TotalVenta", [TotalVenta],
    "TotalGasto", [TotalGasto],
    "Margen€",    [Margen€],
    "Margen%",    [Margen%]
)
ORDER BY Facturacion[year] DESC, Facturacion[Empresa]
```

### Facturación por tipo (P / R) — equivalente a `v_se_facturacion`

```dax
EVALUATE
SUMMARIZECOLUMNS(
    Facturacion[Tipo],
    Facturacion[year],
    "TotalVenta", [TotalVenta]
)
ORDER BY Facturacion[year], Facturacion[Tipo]
```

### Facturación por departamento (PSI 2026)

```dax
EVALUATE
CALCULATETABLE(
    SUMMARIZECOLUMNS(
        Departamentos[Departamento],
        "TotalVenta", [TotalVenta],
        "TotalGasto", [TotalGasto]
    ),
    Facturacion[Empresa] = "Power Solution Iberia",
    Facturacion[year] = 2026
)
ORDER BY [TotalVenta] DESC
```

### Acumulado YTD por mes (PSI 2026)

```dax
EVALUATE
CALCULATETABLE(
    SUMMARIZECOLUMNS(
        Facturacion[AñoMes],
        "AcumuladaVenta", [AcumuladaVenta],
        "AcumuladoGasto", [AcumuladoGasto],
        "AcumuladoMargen%", [AcumuladoMargen%]
    ),
    Facturacion[Empresa] = "Power Solution Iberia",
    Facturacion[year] = 2026
)
ORDER BY Facturacion[AñoMes]
```

### Proyectos con mayor facturación

```dax
EVALUATE
TOPN(
    20,
    SUMMARIZECOLUMNS(
        Facturacion[job],
        Facturacion[Encabezado],
        "TotalVenta", [TotalVenta]
    ),
    [TotalVenta], DESC
)
```

### Verificar alineación con Analytics DB (comparar totales)

```dax
-- En PBI
EVALUATE
SUMMARIZECOLUMNS(
    Facturacion[Tipo],
    "Total", [TotalVenta]
)
```

```sql
-- Equivalente en Analytics DB (PostgreSQL VM 100)
SELECT tipo, ROUND(SUM(facturado::numeric), 2)
FROM v_se_facturacion
WHERE empresa ILIKE '%Iberia%' AND year = 2026
GROUP BY tipo;
```

---

## Medidas disponibles (modelo completo)

Ver spec completo en [`pbix-model-spec.md`](./pbix-model-spec.md).

| Medida | Tabla | Descripción |
|--------|-------|-------------|
| `TotalVenta` | Facturacion | `SUM(facturado)` |
| `TotalGasto` | Facturacion | `SUM(coste)` |
| `Margen€` | Facturacion | `TotalVenta - TotalGasto` |
| `Margen%` | Facturacion | `Margen€ / TotalVenta` |
| `AcumuladaVenta` | Facturacion | YTD de TotalVenta |
| `AcumuladoGasto` | Facturacion | YTD de TotalGasto |
| `AcumuladoMargen%` | Facturacion | YTD de Margen% |
| `AcumuladoMargen€` | Facturacion | YTD de Margen€ |
| `CrecimientoFacturacion%` | Facturacion | YoY sobre `Facturacion_NoCero` |
| `CrecimientoObjetivo%` | Objetivos | Objetivo vs facturación año anterior |
| `MArgenReal%` | Objetivos | `(billingTarget-costTarget)/billingTarget` |
| `Beneficio€` | Objetivos | `billingTarget - costTarget` |
| `Margen%Historico` | HistoricoPlanificacion | Margen histórico |
| `HorasPlanificadasfiltradas` | FacturacionRecursos | Horas por departamento recurso |

## Columnas clave de la tabla `Facturacion`

| Campo | Valores posibles / Descripción |
|-------|-------------------------------|
| `Tipo` | `"P"` (planificación) / `"R"` (real) |
| `Empresa` | `"Power Solution Iberia"` / `"Power Lab Iberia"` |
| `year` | Año numérico (ej: 2026) |
| `month` | Mes numérico (1-12) |
| `AñoMes` | `"07/2026"` (MesTex + "/" + year) |
| `FachaCalculada` | `date(1, month, year)` |
| `job` | Código proyecto BC |
| `Encabezado` | `"JOB --- " + left(descripcion proyecto bc_job, 36)` |
| `CodigoUnicoDepartamento` | `"Empresa:DeptCode"` |
| `Facturado` | Importe facturado ajustado por probabilidad |
| `Coste` | Coste ajustado por probabilidad |
| `%` | Probabilidad (0 = 100%) |

---

## Limitaciones del endpoint `executeQueries`

| Permitido | No permitido |
|-----------|-------------|
| `EVALUATE` | `DEFINE MEASURE` (solo lectura) |
| `SUMMARIZECOLUMNS` | Escritura de datos |
| `CALCULATETABLE` / `FILTER` | DDL (crear tablas/medidas) |
| `TOPN`, `ORDER BY` | Queries sobre múltiples datasets |
| Medidas existentes `[NombreMedida]` | Medidas ad-hoc no definidas en el modelo |

Para medidas ad-hoc, usar `ROW()`:
```dax
EVALUATE ROW("Total", SUMX(Facturacion, Facturacion[Facturado]))
```

---

## Ejecución desde terminal

```bash
# Activar el venv que tiene msal
source ~/.bc_odata_mcp/venv/bin/activate

# Inline (una línea)
python3 -c "
from pathlib import Path; import sys
sys.path.insert(0, str(Path.home() / '.bc_odata_mcp'))
# ... pegar el helper y llamar run_dax(...)
"
```

---

## Troubleshooting

| Error | Causa | Solución |
|-------|-------|----------|
| `AADSTS650057: Invalid resource` | El Client ID no tiene permiso PBI | Usar `ea0616ba-638b-4df5-95b9-636659ae5121` (NO el de `cursor-bc-mcp`) |
| `HTTP 401` | Token expirado / inválido | Borrar `pbi_pbidesktop_cache.bin` y re-autenticar |
| `HTTP 403 PowerBINotAuthorizedException` | El usuario no tiene acceso al dataset | Verificar que la cuenta tiene acceso en `app.powerbi.com` |
| `HTTP 404` | Dataset ID incorrecto | Verificar `bd3dc81a-3bd3-4699-8fc6-f039c79c1821` en la URL del report |
| Código device expirado (15 min) | No se introdujo a tiempo | Reiniciar el script para generar nuevo código |
| `rows: []` | Query válida pero sin datos para ese filtro | Revisar los valores exactos de los campos (mayúsculas, espacios) |

---

**Última actualización:** 2026-08-07  
**Probado con:** Python 3.11 + msal 1.x — dataset "Seguimiento Económico PS"
