"""SQLite connection handling and the schema migration runner.

Plain sqlite3, no ORM. The migration runner is deliberately here on day one:
retrofitting migrations once there is real cached data is the annoying version.

Pattern: a schema_version table plus ordered scripts in app/migrations/, named
NNN_description.sql. Each runs exactly once, in filename order, inside a
transaction. Applied versions are recorded so reruns are no-ops.
"""

import logging
import sqlite3
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from app import settings

log = logging.getLogger(__name__)

_local = threading.local()


def _connect() -> sqlite3.Connection:
    settings.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(settings.DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    # WAL lets the API read while a scheduler job writes, which is the whole
    # concurrency story for this app.
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 5000")
    return conn


def connection() -> sqlite3.Connection:
    """One connection per thread. APScheduler jobs and API requests differ."""
    conn = getattr(_local, "conn", None)
    if conn is None:
        conn = _local.conn = _connect()
    return conn


@contextmanager
def transaction() -> Iterator[sqlite3.Connection]:
    """Run a write inside a transaction, rolling back on failure."""
    conn = connection()
    try:
        with conn:
            yield conn
    except Exception:
        log.exception("transaction rolled back")
        raise


def reset_for_tests(path: Path) -> None:
    """Point the module at a throwaway database. Used only by the test suite."""
    settings.DB_PATH = path
    conn = getattr(_local, "conn", None)
    if conn is not None:
        conn.close()
    _local.conn = None


def _applied_versions(conn: sqlite3.Connection) -> set[str]:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_version (
            version    TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        """
    )
    return {row["version"] for row in conn.execute("SELECT version FROM schema_version")}


def migrate() -> list[str]:
    """Apply every pending migration in filename order. Returns what ran."""
    conn = connection()
    applied = _applied_versions(conn)
    scripts = sorted(settings.MIGRATIONS_DIR.glob("*.sql"))
    ran: list[str] = []

    for script in scripts:
        version = script.stem
        if version in applied:
            continue
        log.info("applying migration %s", version)
        with conn:
            conn.executescript(script.read_text())
            conn.execute("INSERT INTO schema_version (version) VALUES (?)", (version,))
        ran.append(version)

    if ran:
        log.info("applied %d migration(s): %s", len(ran), ", ".join(ran))
    return ran
