"""Per scraper health records, backing /health/sources."""

from datetime import datetime, timezone

from app import db


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def record_attempt(source: str) -> None:
    with db.transaction() as conn:
        conn.execute(
            """
            INSERT INTO source_health (source, last_attempt_at)
            VALUES (?, ?)
            ON CONFLICT(source) DO UPDATE SET last_attempt_at = excluded.last_attempt_at
            """,
            (source, _now()),
        )


def record_success(source: str, record_count: int) -> None:
    with db.transaction() as conn:
        conn.execute(
            """
            INSERT INTO source_health (source, last_success_at, last_attempt_at,
                                       consecutive_failures, last_record_count)
            VALUES (?, ?, ?, 0, ?)
            ON CONFLICT(source) DO UPDATE SET
                last_success_at      = excluded.last_success_at,
                last_attempt_at      = excluded.last_attempt_at,
                consecutive_failures = 0,
                last_record_count    = excluded.last_record_count
            """,
            (source, _now(), _now(), record_count),
        )


def record_failure(source: str, error: str) -> None:
    with db.transaction() as conn:
        conn.execute(
            """
            INSERT INTO source_health (source, last_attempt_at, last_error, last_error_at,
                                       consecutive_failures)
            VALUES (?, ?, ?, ?, 1)
            ON CONFLICT(source) DO UPDATE SET
                last_attempt_at      = excluded.last_attempt_at,
                last_error           = excluded.last_error,
                last_error_at        = excluded.last_error_at,
                consecutive_failures = source_health.consecutive_failures + 1
            """,
            (source, _now(), error[:500], _now()),
        )


def all_sources() -> list[dict]:
    rows = db.connection().execute(
        """
        SELECT source, last_success_at, last_attempt_at, last_error, last_error_at,
               consecutive_failures, last_record_count
        FROM source_health
        ORDER BY source
        """
    )
    return [dict(row) for row in rows]
