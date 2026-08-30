"""Menus with allergen and dietary tags."""

from datetime import date, datetime, timezone

from app import db


def replace_location(location_id: int, dishes: list[dict]) -> int:
    """Swap in a whole location's menu. FD returns a month at a time."""
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with db.transaction() as conn:
        conn.execute("DELETE FROM menu_dish WHERE location_id = ?", (location_id,))
        conn.executemany(
            """
            INSERT OR REPLACE INTO menu_dish
                (location_id, service_date, name, category, allergens, dietary,
                 calories, updated_at)
            VALUES (:location_id, :service_date, :name, :category, :allergens,
                    :dietary, :calories, :updated_at)
            """,
            [{**dish, "location_id": location_id, "updated_at": stamp} for dish in dishes],
        )
    return len(dishes)


def on_date(location_id: int, service_date: date) -> list[dict]:
    rows = db.connection().execute(
        """
        SELECT name, category, allergens, dietary, calories
        FROM menu_dish
        WHERE location_id = ? AND service_date = ?
        ORDER BY category, name
        """,
        (location_id, service_date.isoformat()),
    )
    return [dict(row) for row in rows]


def locations_with_menus() -> list[int]:
    rows = db.connection().execute("SELECT DISTINCT location_id FROM menu_dish")
    return [row["location_id"] for row in rows]


def oldest_refreshed(known: list[int]) -> int | None:
    """Which location to refresh next.

    Locations are fetched one at a time on a rotation rather than all at once,
    because each response is several megabytes. Anything never fetched comes
    first, then the least recently updated.
    """
    if not known:
        return None
    rows = db.connection().execute(
        """
        SELECT location_id, MAX(updated_at) AS seen
        FROM menu_dish
        GROUP BY location_id
        """
    )
    seen = {row["location_id"]: row["seen"] for row in rows}
    never = [loc for loc in known if loc not in seen]
    if never:
        return never[0]
    return min(known, key=lambda loc: seen.get(loc, ""))
