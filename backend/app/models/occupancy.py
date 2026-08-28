"""Live occupancy readings from maps.rit.edu, keyed by mdo_id."""

import json
from datetime import datetime, timedelta, timezone

from app import db


def upsert(reading: dict) -> None:
    with db.transaction() as conn:
        conn.execute(
            """
            INSERT INTO occupancy (mdo_id, count, max_occ, open_status, hourly, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(mdo_id) DO UPDATE SET
                count       = excluded.count,
                max_occ     = excluded.max_occ,
                open_status = excluded.open_status,
                hourly      = excluded.hourly,
                updated_at  = excluded.updated_at
            """,
            (
                reading["mdo_id"],
                reading.get("count"),
                reading.get("max_occ"),
                reading.get("open_status"),
                json.dumps(reading.get("hourly") or []),
                datetime.now(timezone.utc).isoformat(timespec="seconds"),
            ),
        )


def get(mdo_id: int) -> dict | None:
    row = db.connection().execute(
        "SELECT * FROM occupancy WHERE mdo_id = ?", (mdo_id,)
    ).fetchone()
    if not row:
        return None
    out = dict(row)
    out["hourly"] = json.loads(out["hourly"] or "[]")
    return out


def tracked_mdo_ids() -> list[int]:
    """Dining locations that have a maps join key, which is what we poll."""
    rows = db.connection().execute(
        "SELECT DISTINCT mdo_id FROM dining_location WHERE mdo_id IS NOT NULL AND mdo_id > 0"
    )
    return [row["mdo_id"] for row in rows]


def record_probe(mdo_id: int, has_density: bool) -> None:
    """Remember whether this location publishes occupancy at all."""
    with db.transaction() as conn:
        conn.execute(
            """
            INSERT INTO occupancy_probe (mdo_id, has_density, last_probed_at)
            VALUES (?, ?, ?)
            ON CONFLICT(mdo_id) DO UPDATE SET
                has_density    = excluded.has_density,
                last_probed_at = excluded.last_probed_at
            """,
            (
                mdo_id,
                int(has_density),
                datetime.now(timezone.utc).isoformat(timespec="seconds"),
            ),
        )


def due_for_poll(reprobe_after_minutes: int) -> list[int]:
    """Which mdo_ids to fetch this cycle.

    Locations known to publish occupancy are polled every cycle. Locations that
    did not are re-probed occasionally, in case RIT adds a sensor, rather than
    being hammered every five minutes for a key that is not there.
    """
    cutoff = (
        datetime.now(timezone.utc) - timedelta(minutes=reprobe_after_minutes)
    ).isoformat(timespec="seconds")
    rows = db.connection().execute(
        """
        SELECT l.mdo_id
        FROM dining_location l
        LEFT JOIN occupancy_probe p ON p.mdo_id = l.mdo_id
        WHERE l.mdo_id IS NOT NULL AND l.mdo_id > 0
          AND (p.mdo_id IS NULL OR p.has_density = 1 OR p.last_probed_at <= ?)
        ORDER BY l.mdo_id
        """,
        (cutoff,),
    )
    return [row["mdo_id"] for row in rows]
