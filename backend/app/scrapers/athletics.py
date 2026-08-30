"""RIT athletics fixtures.

Source: https://ritathletics.com/calendar.ashx/calendar.ics

This was written off once and should not have been. The Drupal
`node--athletics_event` resource exists but is empty (count 0), and the obvious
Sidearm JSON endpoints all 404, so the first pass concluded there was no feed.
There is: the same site publishes a plain iCal calendar, which parses cleanly
with the machinery already here for CampusGroups. 182 fixtures, all future,
September through March.

Fixtures are events, so they go in the same merged table with `source =
athletics` rather than getting a parallel one. Organizer is set to the sport,
pulled off the summary, so the existing grouping and muting work on them
without any special cases.
"""

import logging
import re
from datetime import datetime

from icalendar import Calendar

from app import http, settings
from app.models import events as events_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "athletics"
FEED_URL = "https://ritathletics.com/calendar.ashx/calendar.ics"

# "Women's Soccer vs Geneseo - Pride Game" -> "Women's Soccer"
_SPORT_RE = re.compile(r"^(.*?)\s+(?:vs\.?|at)\s+", re.I)


def sport_of(summary: str) -> str | None:
    """The sport, so fixtures group and mute like any other organizer."""
    match = _SPORT_RE.match(summary.strip())
    if match and match.group(1):
        return match.group(1).strip()
    # Meets and invitationals do not use vs/at. Fall back to the leading words.
    words = summary.split()
    return " ".join(words[:2]) if len(words) >= 2 else None


def _as_iso(value) -> tuple[str, bool]:
    if isinstance(value, datetime):
        moment = value if value.tzinfo else value.replace(tzinfo=settings.CAMPUS_TZ)
        return moment.astimezone(settings.CAMPUS_TZ).isoformat(), False
    moment = datetime(value.year, value.month, value.day, tzinfo=settings.CAMPUS_TZ)
    return moment.isoformat(), True


async def fetch() -> bytes:
    return await http.get_bytes(FEED_URL)


def parse(raw: bytes) -> list[dict]:
    calendar = Calendar.from_ical(raw)
    out: list[dict] = []

    for component in calendar.walk("VEVENT"):
        uid = str(component.get("UID") or "").strip()
        summary = str(component.get("SUMMARY") or "").strip()
        if not uid or not summary:
            continue

        starts_at, all_day = _as_iso(component.decoded("DTSTART"))
        ends_at = None
        if component.get("DTEND") is not None:
            ends_at, _ = _as_iso(component.decoded("DTEND"))

        sport = sport_of(summary)
        location = str(component.get("LOCATION") or "").strip() or None

        out.append(
            {
                "uid": uid,
                "source": SOURCE,
                "title": summary,
                "description": str(component.get("DESCRIPTION") or "").strip() or None,
                "location": location,
                "building": None,
                "room": None,
                "organizer": sport or "RIT Athletics",
                "organizer_key": (sport or "ATHLETICS").upper().replace(" ", "_"),
                "event_type": "Athletics",
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
        raise ValueError("athletics feed produced zero fixtures")
    events_model.upsert_many(parsed)
    events_model.prune_source(SOURCE, [e["uid"] for e in parsed])
    return len(parsed)


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
