# Exports Superset (pull desde UI)

Snapshots generados por `scripts/pull-superset-dashboard.py`.

## Uso

```bash
# Solo traer estado actual de prod
SUPERSET_URL=http://192.168.36.100:8088 python3 scripts/pull-superset-dashboard.py

# Fallar si difiere del snapshot previous
python3 scripts/pull-superset-dashboard.py --strict
```

El setup regenera el dashboard **después** de hacer pull automático:

```bash
SUPERSET_URL=http://192.168.36.100:8088 python3 scripts/setup-superset-planificacion.py
```

| Variable | Efecto |
|----------|--------|
| `SKIP_SUPERSET_PULL=1` | No hace pull al regenerar |
| `STRICT_UI_SYNC=1` | Aborta regeneración si UI ≠ previous |

## Carpetas

| Ruta | Contenido |
|------|-----------|
| `latest/` | Último pull (dashboard.json, fingerprint.json, charts/) |
| `previous/` | Pull anterior (para diff) |

`latest/` y `previous/` están en `.gitignore` (estado runtime, no fuente de verdad).
La fuente de verdad del dashboard sigue siendo `scripts/setup-superset-planificacion.py`.
