#!/usr/bin/env python3
"""Copia metadata Superset SQLite → Postgres (superset_meta).

Uso (desde Mac o VM 100, con red al Analytics DB y acceso al .db):

  # 1) Esquema destino ya creado con: superset db upgrade (URI Postgres)
  # 2) Ejecutar esta copia (excluye logs por defecto):

  SQLITE_PATH=/path/to/superset.db \\
  PG_DSN=postgresql://postgres:PASS@192.168.36.100:5433/superset_meta \\
  python3 scripts/migrate-superset-metadata-to-postgres.py

Variables:
  SQLITE_PATH   ruta al superset.db (default: data/superset-home/superset.db)
  PG_DSN        DSN psycopg2 al destino
  INCLUDE_LOGS  1 para copiar también tabla logs (default: 0)
  INCLUDE_QUERY 1 para copiar tabla query (default: 0; suele ser voluminosa)
  DRY_RUN       1 solo lista tablas/filas sin escribir
"""

from __future__ import annotations

import os
import sqlite3
import sys
import uuid as uuid_mod
from typing import Any

import psycopg2
from psycopg2.extras import execute_batch, register_uuid

register_uuid()

# Tablas de auditoría / bloat: no aportan a login/dashboards/RLS.
DEFAULT_SKIP = {
    "logs",
    "alembic_version",  # ya la crea `superset db upgrade`
}

# Opcionalmente omitidas por volumen (activar con INCLUDE_QUERY=1).
OPTIONAL_SKIP = {"query"}


def env_flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "1" if default else "0").strip().lower()
    return raw in {"1", "true", "yes", "y", "s"}


def sqlite_tables(conn: sqlite3.Connection) -> list[str]:
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
        "ORDER BY name"
    )
    return [r[0] for r in cur.fetchall()]


def pg_tables(conn: Any) -> set[str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT tablename FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY tablename
            """
        )
        return {r[0] for r in cur.fetchall()}


def table_columns_sqlite(conn: sqlite3.Connection, table: str) -> list[str]:
    cur = conn.execute(f'PRAGMA table_info("{table}")')
    return [r[1] for r in cur.fetchall()]


def table_columns_pg(conn: Any, table: str) -> list[str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            ORDER BY ordinal_position
            """,
            (table,),
        )
        return [r[0] for r in cur.fetchall()]


def table_pg_types(conn: Any, table: str) -> dict[str, str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT column_name, data_type, udt_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            """,
            (table,),
        )
        out: dict[str, str] = {}
        for name, data_type, udt_name in cur.fetchall():
            out[name] = (udt_name or data_type or "").lower()
        return out


def coerce_row(
    row: tuple[Any, ...], cols: list[str], pg_types: dict[str, str]
) -> tuple[Any, ...]:
    """Adapta tipos SQLite → Postgres (bool, uuid, json, etc.)."""
    import json

    out: list[Any] = []
    for val, col in zip(row, cols):
        pg_t = pg_types.get(col, "")
        if val is None:
            out.append(None)
            continue
        if pg_t in {"bool", "boolean"}:
            if isinstance(val, bool):
                out.append(val)
            else:
                out.append(str(val).strip().lower() in {"1", "true", "t", "yes", "y"})
        elif pg_t == "uuid":
            if isinstance(val, uuid_mod.UUID):
                out.append(str(val))
            elif isinstance(val, (bytes, bytearray, memoryview)):
                raw = bytes(val)
                out.append(
                    str(uuid_mod.UUID(bytes=raw))
                    if len(raw) == 16
                    else str(uuid_mod.UUID(raw.decode()))
                )
            else:
                out.append(str(uuid_mod.UUID(str(val))))
        elif pg_t in {"json", "jsonb"}:
            if isinstance(val, (dict, list)):
                out.append(json.dumps(val))
            elif isinstance(val, (bytes, bytearray, memoryview)):
                out.append(bytes(val).decode("utf-8", errors="replace"))
            else:
                out.append(val)
        elif pg_t in {"bytea"} and isinstance(val, str):
            out.append(val.encode("utf-8"))
        else:
            # Texto/números: si viene bytes y el destino no es bytea, decodificar.
            if isinstance(val, (bytes, bytearray, memoryview)) and pg_t not in {
                "bytea"
            }:
                try:
                    out.append(bytes(val).decode("utf-8"))
                except Exception:
                    out.append(bytes(val))
            else:
                out.append(val)
    return tuple(out)


def reset_sequence(conn: Any, table: str, pk_col: str = "id") -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT pg_get_serial_sequence(%s, %s)
            """,
            (table, pk_col),
        )
        row = cur.fetchone()
        seq = row[0] if row else None
        if not seq:
            return
        cur.execute(f'SELECT COALESCE(MAX("{pk_col}"), 0) FROM "{table}"')
        max_id = cur.fetchone()[0] or 0
        if max_id <= 0:
            # Secuencia vacía: próximo nextval = 1
            cur.execute("SELECT setval(%s, 1, false)", (seq,))
        else:
            cur.execute("SELECT setval(%s, %s, true)", (seq, max_id))


def copy_table(
    sqlite_conn: sqlite3.Connection,
    pg_conn: Any,
    table: str,
    dry_run: bool,
) -> int:
    sq_cols = table_columns_sqlite(sqlite_conn, table)
    pg_cols = table_columns_pg(pg_conn, table)
    cols = [c for c in sq_cols if c in pg_cols]
    if not cols:
        print(f"  SKIP {table}: sin columnas en común")
        return 0

    col_sql = ", ".join(f'"{c}"' for c in cols)
    rows = sqlite_conn.execute(f'SELECT {col_sql} FROM "{table}"').fetchall()
    print(f"  {table}: {len(rows)} filas → cols={len(cols)}")
    if dry_run or not rows:
        return len(rows)

    pg_types = table_pg_types(pg_conn, table)
    coerced = [coerce_row(tuple(r), cols, pg_types) for r in rows]

    placeholders = ", ".join(["%s"] * len(cols))
    sql = f'INSERT INTO "{table}" ({col_sql}) VALUES ({placeholders})'

    with pg_conn.cursor() as cur:
        # NO truncar aquí: un TRUNCATE CASCADE por tabla borra filas ya migradas
        # (p. ej. truncar `tables` elimina `slices`). El truncate global va al inicio.
        execute_batch(cur, sql, coerced, page_size=500)
    return len(rows)


def main() -> int:
    sqlite_path = os.environ.get(
        "SQLITE_PATH",
        os.path.join(
            os.path.dirname(__file__), "..", "data", "superset-home", "superset.db"
        ),
    )
    sqlite_path = os.path.abspath(sqlite_path)
    pg_dsn = os.environ.get(
        "PG_DSN",
        "postgresql://postgres:SuperSecurePassword2025@192.168.36.100:5433/superset_meta",
    )
    dry_run = env_flag("DRY_RUN")
    include_logs = env_flag("INCLUDE_LOGS")
    include_query = env_flag("INCLUDE_QUERY")

    skip = set(DEFAULT_SKIP)
    if not include_logs:
        skip.add("logs")
    if not include_query:
        skip |= OPTIONAL_SKIP

    if not os.path.isfile(sqlite_path):
        print(f"ERROR: no existe SQLITE_PATH={sqlite_path}", file=sys.stderr)
        return 1

    print(f"SQLite: {sqlite_path}")
    print(f"Postgres: {pg_dsn.split('@')[-1]}")
    print(f"DRY_RUN={dry_run} skip={sorted(skip)}")

    sq = sqlite3.connect(sqlite_path)
    sq.row_factory = sqlite3.Row
    pg = psycopg2.connect(pg_dsn)
    pg.autocommit = False

    try:
        src_tables = sqlite_tables(sq)
        dst_tables = pg_tables(pg)
        print(f"Tablas SQLite={len(src_tables)} Postgres={len(dst_tables)}")

        missing_in_pg = [t for t in src_tables if t not in dst_tables and t not in skip]
        if missing_in_pg:
            print(
                "AVISO: tablas en SQLite sin equivalente en Postgres "
                f"(omitidas): {missing_in_pg}"
            )

        # Orden: primero tablas sin dependencias fuertes; TRUNCATE CASCADE ayuda.
        # Preferir ab_* y luego el resto alfabético.
        prefer = [
            t
            for t in src_tables
            if t in dst_tables and t not in skip and t.startswith("ab_")
        ]
        rest = [
            t
            for t in src_tables
            if t in dst_tables and t not in skip and t not in prefer
        ]
        ordered = prefer + rest

        if not dry_run:
            with pg.cursor() as cur:
                # Permite INSERT fuera de orden de FKs + truncate limpio una vez.
                cur.execute("SET session_replication_role = replica")
                for table in ordered:
                    cur.execute(f'TRUNCATE TABLE "{table}" CASCADE')

        total = 0
        for table in ordered:
            total += copy_table(sq, pg, table, dry_run=dry_run)

        if not dry_run:
            # Reset secuencias de PKs habituales.
            for table in ordered:
                pg_cols = set(table_columns_pg(pg, table))
                if "id" in pg_cols:
                    reset_sequence(pg, table, "id")
            with pg.cursor() as cur:
                cur.execute("SET session_replication_role = DEFAULT")
            pg.commit()
            print(f"OK: migradas ~{total} filas en {len(ordered)} tablas")
        else:
            print(f"DRY_RUN: {len(ordered)} tablas / ~{total} filas (sin escribir)")
        return 0
    except Exception:
        pg.rollback()
        raise
    finally:
        sq.close()
        pg.close()


if __name__ == "__main__":
    raise SystemExit(main())
