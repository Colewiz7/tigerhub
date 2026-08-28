"""SHED makerspace equipment availability."""

from datetime import datetime, timezone

from app import db


def replace_all(items: list[dict]) -> None:
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with db.transaction() as conn:
        conn.execute("DELETE FROM equipment")
        conn.executemany(
            """
            INSERT INTO equipment (id, name, sub_name, room, in_use,
                                   num_available, num_in_use, updated_at)
            VALUES (:id, :name, :sub_name, :room, :in_use,
                    :num_available, :num_in_use, :updated_at)
            """,
            [{**item, "updated_at": stamp} for item in items],
        )


def list_equipment(room: str | None = None) -> list[dict]:
    sql = "SELECT * FROM equipment"
    params: list = []
    if room:
        sql += " WHERE room = ?"
        params.append(room)
    sql += " ORDER BY room, name"
    return [dict(row) for row in db.connection().execute(sql, params)]


def room_summary() -> list[dict]:
    rows = db.connection().execute(
        """
        SELECT room,
               COUNT(*)               AS machines,
               SUM(num_available)     AS available,
               SUM(num_in_use)        AS in_use
        FROM equipment
        GROUP BY room
        ORDER BY room
        """
    )
    return [dict(row) for row in rows]
