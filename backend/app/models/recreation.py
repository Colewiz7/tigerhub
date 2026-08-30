"""Gym, fitness and pool hours."""

from datetime import date, datetime, timezone

from app import db


def replace_all(rows: list[dict]) -> None:
    """Swap the whole table. The source publishes a rolling seven days, so
    yesterday's rows are not worth keeping."""
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with db.transaction() as conn:
        conn.execute("DELETE FROM recreation_hours")
        conn.executemany(
            """
            INSERT INTO recreation_hours
                (facility, service_date, opens_at, closes_at, closed, note, updated_at)
            VALUES (:facility, :service_date, :opens_at, :closes_at, :closed, :note, :updated_at)
            """,
            [{**row, "updated_at": stamp} for row in rows],
        )


def between(start: date, end: date) -> list[dict]:
    rows = db.connection().execute(
        """
        SELECT facility, service_date, opens_at, closes_at, closed, note
        FROM recreation_hours
        WHERE service_date BETWEEN ? AND ?
        ORDER BY facility, service_date, opens_at
        """,
        (start.isoformat(), end.isoformat()),
    )
    return [dict(row) for row in rows]


def facilities() -> list[str]:
    rows = db.connection().execute(
        "SELECT DISTINCT facility FROM recreation_hours ORDER BY facility"
    )
    return [row["facility"] for row in rows]
