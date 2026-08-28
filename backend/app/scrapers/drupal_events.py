"""Official RIT events from the public Drupal JSON:API.

Endpoint: https://www.rit.edu/jsonapi/node/event
Verified 2026-08-28. This replaced the planned HTML scrape entirely: the
JSON:API module is publicly exposed and returns about 450 structured events.

Paginates at 50, so page[limit] is set explicitly and links.next is followed.
Sparse fieldsets keep the payload small, no image data is requested.
"""

import logging
from datetime import datetime, time

from app import http, settings
from app.models import events as events_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "drupal"
BASE_URL = "https://www.rit.edu/jsonapi/node/event"

FIELDS = ",".join(
    [
        "title",
        "body",
        "field_start_date",
        "field_start_time",
        "field_end_date",
        "field_end_time",
        "field_building",
        "field_room_location",
        "field_event_type",
        "field_link",
        "path",
        "changed",
    ]
)

PAGE_LIMIT = 50
MAX_PAGES = 20  # backstop so a pagination bug cannot loop forever


async def fetch() -> list[dict]:
    """Follow links.next until exhausted, returning raw JSON:API records."""
    url: str | None = BASE_URL
    params: dict | None = {"page[limit]": PAGE_LIMIT, "fields[node--event]": FIELDS}
    records: list[dict] = []

    for _ in range(MAX_PAGES):
        if not url:
            break
        payload = await http.get_json(url, params=params)
        records.extend(payload.get("data") or [])
        nxt = (payload.get("links") or {}).get("next")
        # links.next already carries the full query string.
        url = nxt.get("href") if isinstance(nxt, dict) else None
        params = None

    return records


def _combine(day: str | None, clock: str | None) -> tuple[str | None, bool]:
    """Drupal splits date and time. Recombine into one campus local timestamp."""
    if not day:
        return None, False
    try:
        parsed_day = datetime.fromisoformat(day).date()
    except ValueError:
        return None, False

    if not clock:
        return datetime.combine(parsed_day, time.min, tzinfo=settings.CAMPUS_TZ).isoformat(), True

    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            parsed_time = datetime.strptime(clock, fmt).time()
        except ValueError:
            continue
        return datetime.combine(parsed_day, parsed_time, tzinfo=settings.CAMPUS_TZ).isoformat(), False

    return datetime.combine(parsed_day, time.min, tzinfo=settings.CAMPUS_TZ).isoformat(), True


def parse(records: list[dict]) -> list[dict]:
    out: list[dict] = []

    for record in records:
        attrs = record.get("attributes") or {}
        starts_at, all_day = _combine(attrs.get("field_start_date"), attrs.get("field_start_time"))
        if not starts_at:
            continue
        ends_at, _ = _combine(attrs.get("field_end_date"), attrs.get("field_end_time"))

        body = attrs.get("body") or {}
        link = attrs.get("field_link") or {}
        path = attrs.get("path") or {}
        alias = path.get("alias")

        out.append(
            {
                "uid": record.get("id") or "",
                "source": SOURCE,
                "title": (attrs.get("title") or "").strip(),
                "description": (body.get("value") or None) if isinstance(body, dict) else None,
                "location": attrs.get("field_room_location"),
                "building": attrs.get("field_building"),
                "room": attrs.get("field_room_location"),
                # Drupal events are university published, not club published.
                "organizer": "RIT",
                "organizer_key": "RIT",
                "event_type": attrs.get("field_event_type"),
                "url": (link.get("uri") if isinstance(link, dict) else None)
                or (f"https://www.rit.edu{alias}" if alias else None),
                "starts_at": starts_at,
                "ends_at": ends_at,
                "all_day": int(all_day),
            }
        )

    return [e for e in out if e["uid"]]


async def scrape() -> int:
    parsed = parse(await fetch())
    if not parsed:
        raise ValueError("Drupal JSON:API produced zero events")
    events_model.upsert_many(parsed)
    events_model.prune_source(SOURCE, [e["uid"] for e in parsed])
    return len(parsed)


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
