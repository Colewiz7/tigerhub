"""CampusGroups student club events, from the public all events iCal feed.

Feed: https://campusgroups.rit.edu/ical/rit/ical_rit.ics (302s to a CDN).
Verified 2026-08-28: 921 events, every field present on 100% of them, and zero
RRULEs because recurrences arrive pre expanded. No recurrence engine needed.

The X-CG-CATEGORY=club_acronym parameter is kept as organizer_key. It joins
cleanly to the Drupal node--student_club slug (60 of 60 in the feed), which is
what lets the client show real club names and mute a noisy organizer.
"""

import logging
from datetime import date, datetime, time

from icalendar import Calendar

from app import http, settings
from app.models import events as events_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "campusgroups"
FEED_URL = "https://campusgroups.rit.edu/ical/rit/ical_rit.ics"


async def fetch() -> bytes:
    return await http.get_bytes(FEED_URL)


def _as_datetime(value) -> tuple[str, bool]:
    """Return an ISO timestamp plus whether this was an all day entry."""
    if isinstance(value, datetime):
        moment = value
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=settings.CAMPUS_TZ)
        return moment.isoformat(), False
    if isinstance(value, date):
        moment = datetime.combine(value, time.min, tzinfo=settings.CAMPUS_TZ)
        return moment.isoformat(), True
    raise TypeError(f"unsupported date value: {value!r}")


def _categories(component) -> tuple[str | None, str | None]:
    """Pull the club acronym and the event type out of CATEGORIES."""
    raw = component.get("CATEGORIES")
    if raw is None:
        return None, None
    items = raw if isinstance(raw, list) else [raw]

    acronym = event_type = None
    for item in items:
        kind = item.params.get("X-CG-CATEGORY")
        try:
            value = item.to_ical().decode()
        except AttributeError:
            value = str(item)
        if kind == "club_acronym":
            acronym = value
        elif kind == "event_type":
            event_type = value
    return acronym, event_type


def parse(raw: bytes) -> list[dict]:
    calendar = Calendar.from_ical(raw)
    out: list[dict] = []

    for component in calendar.walk("VEVENT"):
        uid = str(component.get("UID") or "").strip()
        if not uid:
            continue

        starts_at, all_day = _as_datetime(component.decoded("DTSTART"))
        ends_at = None
        if component.get("DTEND") is not None:
            ends_at, _ = _as_datetime(component.decoded("DTEND"))

        organizer_raw = component.get("ORGANIZER")
        organizer = None
        if organizer_raw is not None:
            organizer = organizer_raw.params.get("CN") or None

        acronym, event_type = _categories(component)

        out.append(
            {
                "uid": uid,
                "source": SOURCE,
                "title": str(component.get("SUMMARY") or "").strip(),
                "description": str(component.get("DESCRIPTION") or "").strip() or None,
                "location": str(component.get("LOCATION") or "").strip() or None,
                "building": None,
                "room": None,
                "organizer": organizer,
                "organizer_key": acronym.upper() if acronym else None,
                "event_type": event_type,
                "url": str(component.get("URL") or "").strip() or None,
                "starts_at": starts_at,
                "ends_at": ends_at,
                "all_day": int(all_day),
            }
        )

    return out


async def scrape() -> int:
    parsed = parse(await fetch())
    if not parsed:
        raise ValueError("iCal feed produced zero events")
    events_model.upsert_many(parsed)
    events_model.prune_source(SOURCE, [e["uid"] for e in parsed])
    return len(parsed)


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
