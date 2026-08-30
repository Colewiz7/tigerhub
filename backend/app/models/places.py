"""Campus points of interest."""

from datetime import datetime, timezone

from app import db


def replace_kind(kind: str, places: list[dict]) -> int:
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with db.transaction() as conn:
        conn.execute("DELETE FROM campus_place WHERE kind = ?", (kind,))
        conn.executemany(
            """
            INSERT OR REPLACE INTO campus_place
                (id, kind, kind_name, name, building, building_no, floor, room,
                 note, mdo_id, updated_at)
            VALUES (:id, :kind, :kind_name, :name, :building, :building_no,
                    :floor, :room, :note, :mdo_id, :updated_at)
            """,
            [{**place, "kind": kind, "updated_at": stamp} for place in places],
        )
    return len(places)


def kinds() -> list[dict]:
    rows = db.connection().execute(
        """
        SELECT kind, kind_name, COUNT(*) AS count
        FROM campus_place
        GROUP BY kind, kind_name
        ORDER BY kind_name
        """
    )
    return [dict(row) for row in rows]


def of_kind(kind: str, building: str | None = None) -> list[dict]:
    sql = """
        SELECT id, kind, kind_name, name, building, building_no, floor, room,
               note, mdo_id
        FROM campus_place
        WHERE kind = ?
    """
    params: list = [kind]
    if building:
        sql += " AND building = ?"
        params.append(building.upper())
    sql += " ORDER BY building, floor, name"
    return [dict(row) for row in db.connection().execute(sql, params)]
