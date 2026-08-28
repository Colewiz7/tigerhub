"""The merged events table.

One table, both feeds, distinguished by `source`. No dedupe for MVP by design:
the overlap between CampusGroups and Drupal stays observable until there is a
reason to write fuzzy matching.
"""

from datetime import datetime, timezone

from app import db


def upsert_many(events: list[dict]) -> int:
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with db.transaction() as conn:
        conn.executemany(
            """
            INSERT INTO event (uid, source, title, description, location, building, room,
                               organizer, organizer_key, event_type, url,
                               starts_at, ends_at, all_day, updated_at)
            VALUES (:uid, :source, :title, :description, :location, :building, :room,
                    :organizer, :organizer_key, :event_type, :url,
                    :starts_at, :ends_at, :all_day, :updated_at)
            ON CONFLICT(source, uid) DO UPDATE SET
                title         = excluded.title,
                description   = excluded.description,
                location      = excluded.location,
                building      = excluded.building,
                room          = excluded.room,
                organizer     = excluded.organizer,
                organizer_key = excluded.organizer_key,
                event_type    = excluded.event_type,
                url           = excluded.url,
                starts_at     = excluded.starts_at,
                ends_at       = excluded.ends_at,
                all_day       = excluded.all_day,
                updated_at    = excluded.updated_at
            """,
            [{**e, "updated_at": stamp} for e in events],
        )
    return len(events)


def prune_source(source: str, keep_uids: list[str]) -> int:
    """Drop rows for a source that the latest fetch no longer lists.

    Guard: if the fetch returned nothing, keep what is cached rather than
    wiping the table on a bad upstream response.
    """
    if not keep_uids:
        return 0
    placeholders = ",".join("?" for _ in keep_uids)
    with db.transaction() as conn:
        cur = conn.execute(
            f"DELETE FROM event WHERE source = ? AND uid NOT IN ({placeholders})",
            [source, *keep_uids],
        )
    return cur.rowcount


def query(
    start: datetime,
    end: datetime,
    sources: list[str] | None = None,
    organizer_keys: list[str] | None = None,
    exclude_organizer_keys: list[str] | None = None,
    limit: int = 500,
) -> list[dict]:
    sql = """
        SELECT uid, source, title, description, location, building, room, organizer,
               organizer_key, event_type, url, starts_at, ends_at, all_day
        FROM event
        WHERE starts_at >= ? AND starts_at < ?
    """
    params: list = [start.isoformat(), end.isoformat()]

    if sources:
        sql += f" AND source IN ({','.join('?' for _ in sources)})"
        params.extend(sources)
    if organizer_keys:
        sql += f" AND organizer_key IN ({','.join('?' for _ in organizer_keys)})"
        params.extend(organizer_keys)
    if exclude_organizer_keys:
        sql += f" AND (organizer_key IS NULL OR organizer_key NOT IN "
        sql += f"({','.join('?' for _ in exclude_organizer_keys)}))"
        params.extend(exclude_organizer_keys)

    sql += " ORDER BY starts_at LIMIT ?"
    params.append(limit)
    return [dict(row) for row in db.connection().execute(sql, params)]


def organizers() -> list[dict]:
    """Organizer facets, so the client can group, collapse, or mute a source."""
    rows = db.connection().execute(
        """
        SELECT organizer_key, organizer, source, COUNT(*) AS event_count
        FROM event
        WHERE organizer IS NOT NULL
        GROUP BY organizer_key, organizer, source
        ORDER BY event_count DESC
        """
    )
    return [dict(row) for row in rows]
