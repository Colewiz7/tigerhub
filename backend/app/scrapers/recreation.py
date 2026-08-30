"""Gym, fitness and pool hours from RIT Recreation and Wellness.

Source: https://www.rit.edu/recreationwellness/facility-hours

This is an HTML scrape rather than an API, because RIT publishes no feed for
it. The markup is stable and well structured though: each facility is a named
collapse panel followed by a `table.seven-day-schedule` of day and hours pairs,
so this targets that structure rather than guessing at text positions.

Hour strings are prose and can hold several sessions in one cell, for example
the Aquatics Center's "6:45am - 8:45am, 12pm - 1:45pm, 7pm - 10pm". Each comma
separated segment becomes its own span, which is what makes a pool schedule
usable rather than a single misleading open-to-close range.
"""

import logging
import re
from datetime import date, datetime, timedelta

from app import http, settings
from app.models import recreation as recreation_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "recreation_hours"
URL = "https://www.rit.edu/recreationwellness/facility-hours"

_WEEKDAYS = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}

# Facility name, then the schedule table that belongs to it.
_NAME_RE = re.compile(r'<span class="overflow-hidden">\s*(.*?)\s*</span>', re.S)
_TABLE_RE = re.compile(
    r'<table[^>]*class="[^"]*seven-day-schedule[^"]*"[^>]*>(.*?)</table>', re.S
)
_ROW_RE = re.compile(r"<tr>\s*<th>(.*?)</th>\s*<td>(.*?)</td>\s*</tr>", re.S)
_TAGS_RE = re.compile(r"<[^>]+>")


def _text(raw: str) -> str:
    """Strip tags and entities down to a single clean line."""
    import html as html_lib

    value = _TAGS_RE.sub(" ", raw)
    value = html_lib.unescape(value)
    return re.sub(r"\s+", " ", value).strip()


def parse_time(token: str) -> str | None:
    """Turn '6:45am', '10am', '12pm', 'noon' into 'HH:MM'."""
    value = token.strip().lower().replace(".", "")
    if value in ("noon", "12noon"):
        return "12:00"
    if value == "midnight":
        return "00:00"

    match = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", value)
    if not match:
        return None
    hour = int(match.group(1))
    minute = int(match.group(2) or 0)
    meridiem = match.group(3)

    if meridiem == "pm" and hour != 12:
        hour += 12
    elif meridiem == "am" and hour == 12:
        hour = 0
    if hour > 23 or minute > 59:
        return None
    return f"{hour:02d}:{minute:02d}"


def parse_hours_cell(cell: str) -> list[dict]:
    """Split one cell into concrete spans. Closed yields an empty list."""
    value = _text(cell)
    if not value or re.search(r"closed", value, re.I):
        return []

    spans: list[dict] = []
    for segment in value.split(","):
        # An en dash or hyphen separates the two ends.
        parts = re.split(r"\s*[-–—]\s*", segment.strip())
        if len(parts) != 2:
            continue
        opens = parse_time(parts[0])
        closes = parse_time(parts[1])
        if opens and closes:
            spans.append({"opens_at": opens, "closes_at": closes})
    return spans


_DAY_RE = re.compile(
    r"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b", re.I
)


def _weekday_of(label: str) -> int | None:
    """'Saturday (Today)' becomes 5.

    Scans for a weekday anywhere in the label rather than taking the first
    word, because the header row runs into the first data row in this markup
    and yields 'Date Hours Saturday (Today)'. Taking the first word dropped
    today's row entirely.
    """
    match = _DAY_RE.search(_text(label))
    return _WEEKDAYS[match.group(1).lower()] if match else None


def _resolve_date(weekday: int, today: date) -> date:
    """The page shows the next seven days starting today."""
    return today + timedelta(days=(weekday - today.weekday()) % 7)


async def fetch() -> str:
    return await http.get_text(URL)


def parse(html_text: str, today: date | None = None) -> list[dict]:
    """Return one row per facility per date per span."""
    reference = today or datetime.now(settings.CAMPUS_TZ).date()

    # Walk names and tables together in document order, pairing each table with
    # the closest preceding name.
    names = [(m.start(), _text(m.group(1))) for m in _NAME_RE.finditer(html_text)]
    rows: list[dict] = []

    for table in _TABLE_RE.finditer(html_text):
        preceding = [name for position, name in names if position < table.start()]
        facility = preceding[-1] if preceding else None
        if not facility:
            continue

        for day_label, hours_cell in _ROW_RE.findall(table.group(1)):
            weekday = _weekday_of(day_label)
            if weekday is None:
                continue
            service_date = _resolve_date(weekday, reference)
            spans = parse_hours_cell(hours_cell)

            if not spans:
                rows.append(
                    {
                        "facility": facility,
                        "service_date": service_date.isoformat(),
                        "opens_at": None,
                        "closes_at": None,
                        "closed": 1,
                        "note": _text(hours_cell) or "Closed",
                    }
                )
                continue

            for span in spans:
                rows.append(
                    {
                        "facility": facility,
                        "service_date": service_date.isoformat(),
                        "opens_at": span["opens_at"],
                        "closes_at": span["closes_at"],
                        "closed": 0,
                        "note": None,
                    }
                )

    return rows


async def scrape() -> int:
    rows = parse(await fetch())
    if not rows:
        raise ValueError("recreation hours page produced zero rows")
    recreation_model.replace_all(rows)
    return len(rows)


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
