"""Dining locations, resolved hours, and menu items."""

from datetime import date, datetime, timezone

from app import db
from app.hours import Span


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def replace_locations(locations: list[dict]) -> None:
    """Upsert locations. Rows are never deleted, so a location that vanishes
    from one payload does not disappear from the cache mid outage."""
    stamp = _now()
    with db.transaction() as conn:
        conn.executemany(
            """
            INSERT INTO dining_location (id, name, summary, description, maps_url,
                                         department, mdo_id, updated_at)
            VALUES (:id, :name, :summary, :description, :maps_url,
                    :department, :mdo_id, :updated_at)
            ON CONFLICT(id) DO UPDATE SET
                name        = excluded.name,
                summary     = excluded.summary,
                description = excluded.description,
                maps_url    = excluded.maps_url,
                department  = excluded.department,
                mdo_id      = excluded.mdo_id,
                updated_at  = excluded.updated_at
            """,
            [{**loc, "updated_at": stamp} for loc in locations],
        )


def replace_hours(location_id: int, spans: list[Span], window: tuple[date, date]) -> None:
    """Swap in freshly resolved spans for one location over a date window."""
    with db.transaction() as conn:
        conn.execute(
            "DELETE FROM dining_hours WHERE location_id = ? AND service_date BETWEEN ? AND ?",
            (location_id, window[0].isoformat(), window[1].isoformat()),
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO dining_hours
                (location_id, service_date, opens_at, closes_at, closes_next_day,
                 menu_types, source_event_id, is_exception)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    location_id,
                    s.service_date.isoformat(),
                    s.opens_at.isoformat(),
                    s.closes_at.isoformat(),
                    int(s.closes_next_day),
                    ",".join(s.menu_types) or None,
                    s.source_event_id,
                    int(s.is_exception),
                )
                for s in spans
            ],
        )


def replace_menu_items(location_id: int, service_date: date, items: list[dict]) -> None:
    with db.transaction() as conn:
        conn.execute(
            "DELETE FROM dining_menu_item WHERE location_id = ? AND service_date = ?",
            (location_id, service_date.isoformat()),
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO dining_menu_item
                (id, location_id, service_date, name, description, price, category)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    item["id"],
                    location_id,
                    service_date.isoformat(),
                    item["name"],
                    item.get("description"),
                    item.get("price"),
                    item.get("category"),
                )
                for item in items
            ],
        )


def list_locations() -> list[dict]:
    rows = db.connection().execute(
        """
        SELECT l.id, l.name, l.summary, l.description, l.maps_url, l.department,
               l.mdo_id, l.updated_at,
               o.count AS occupancy_count, o.max_occ AS occupancy_max,
               o.open_status AS occupancy_status
        FROM dining_location l
        LEFT JOIN occupancy o ON o.mdo_id = l.mdo_id
        ORDER BY l.name
        """
    )
    return [dict(row) for row in rows]


def get_location(location_id: int) -> dict | None:
    row = db.connection().execute(
        "SELECT * FROM dining_location WHERE id = ?", (location_id,)
    ).fetchone()
    return dict(row) if row else None


def hours_between(start: date, end: date, location_id: int | None = None) -> list[dict]:
    sql = """
        SELECT location_id, service_date, opens_at, closes_at, closes_next_day,
               menu_types, is_exception
        FROM dining_hours
        WHERE service_date BETWEEN ? AND ?
    """
    params: list = [start.isoformat(), end.isoformat()]
    if location_id is not None:
        sql += " AND location_id = ?"
        params.append(location_id)
    sql += " ORDER BY location_id, service_date, opens_at"
    return [dict(row) for row in db.connection().execute(sql, params)]


def menu_items_on(service_date: date, category: str | None = None) -> list[dict]:
    sql = """
        SELECT m.id, m.location_id, l.name AS location_name, m.service_date,
               m.name, m.description, m.price, m.category
        FROM dining_menu_item m
        JOIN dining_location l ON l.id = m.location_id
        WHERE m.service_date = ?
    """
    params: list = [service_date.isoformat()]
    if category is not None:
        sql += " AND m.category = ?"
        params.append(category)
    sql += " ORDER BY l.name, m.name"
    return [dict(row) for row in db.connection().execute(sql, params)]
