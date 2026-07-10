"""Lightweight in-place migrations for columns added after a table shipped.

`Base.metadata.create_all` only creates missing tables — it never alters
existing ones — so new columns are added here with best-effort ALTER TABLE
(one autocommit statement each; "already exists" errors are ignored).
"""

import logging

from sqlalchemy import text
from sqlalchemy.engine import Engine

logger = logging.getLogger(__name__)

# (table, column, DDL type/default)
_COLUMNS = [
    ("portfolio_items", "broker", "VARCHAR"),
    ("portfolio_items", "status", "VARCHAR DEFAULT 'active'"),
    ("portfolio_items", "source", "VARCHAR DEFAULT 'manual'"),
    ("portfolio_items", "updated_at", "TIMESTAMP"),
    ("fortune_results", "session", "VARCHAR DEFAULT 'day'"),
]

_BACKFILLS = [
    "UPDATE portfolio_items SET status = 'active' WHERE status IS NULL",
    "UPDATE portfolio_items SET source = 'manual' WHERE source IS NULL",
    "UPDATE fortune_results SET session = 'day' WHERE session IS NULL",
]


def run_light_migrations(engine: Engine) -> None:
    with engine.connect() as conn:
        conn = conn.execution_options(isolation_level="AUTOCOMMIT")
        for table, column, ddl in _COLUMNS:
            try:
                conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}"))
                logger.info("Migration: added %s.%s", table, column)
            except Exception:
                pass  # column already exists
        for stmt in _BACKFILLS:
            try:
                conn.execute(text(stmt))
            except Exception:
                logger.exception("Migration backfill failed: %s", stmt)
