"""Resolve the TigerCenter hours recurrence model into concrete daily spans.

TigerCenter does not publish a list of days. It publishes, per location, a set
of `events`, each being a term long window (startDate to endDate) plus a
weekday mask plus a daily open and close time, plus dated `exceptions` that
override that window on specific dates.

Everything here turns that into concrete open/close spans per date, so the
client never does date math. An "is it open right now" boolean and the next
transition time are derived from those spans.

Overnight spans (Midnight Oil closes at 1 a.m.) are represented by
closes_next_day, meaning the close time belongs to the following calendar day.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

from app import settings

WEEKDAYS = [
    "MONDAY",
    "TUESDAY",
    "WEDNESDAY",
    "THURSDAY",
    "FRIDAY",
    "SATURDAY",
    "SUNDAY",
]


@dataclass(frozen=True)
class Span:
    """One concrete open period on one calendar date."""

    service_date: date
    opens_at: time
    closes_at: time
    closes_next_day: bool = False
    menu_types: tuple[str, ...] = ()
    source_event_id: int | None = None
    is_exception: bool = False

    def start_dt(self) -> datetime:
        return datetime.combine(self.service_date, self.opens_at, tzinfo=settings.CAMPUS_TZ)

    def end_dt(self) -> datetime:
        day = self.service_date + timedelta(days=1) if self.closes_next_day else self.service_date
        return datetime.combine(day, self.closes_at, tzinfo=settings.CAMPUS_TZ)

    def contains(self, moment: datetime) -> bool:
        return self.start_dt() <= moment < self.end_dt()


@dataclass
class OpenState:
    """What the client actually renders: a boolean and the next transition."""

    is_open: bool
    opens_at: datetime | None = None
    closes_at: datetime | None = None
    next_transition: datetime | None = None
    spans_today: list[Span] = field(default_factory=list)


def _parse_date(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None


def _parse_time(value: str | None) -> time | None:
    if not value:
        return None
    # TigerCenter sends "HH:MM:SS". Tolerate a missing seconds component.
    parts = [int(p) for p in value.split(":")]
    while len(parts) < 3:
        parts.append(0)
    hour, minute, second = parts[:3]
    # A 24:00:00 close means end of day, which Python's time cannot hold.
    if hour >= 24:
        hour, minute, second = 23, 59, 59
    return time(hour, minute, second)


def _covers(entry: dict, day: date) -> bool:
    """Does this event or exception apply on the given date?"""
    start = _parse_date(entry.get("startDate"))
    end = _parse_date(entry.get("endDate"))
    if start and day < start:
        return False
    # `infinite` events have no meaningful end date.
    if end and not entry.get("infinite") and day > end:
        return False
    days = entry.get("daysOfWeek") or []
    return WEEKDAYS[day.weekday()] in days


def _span_from(entry: dict, day: date, is_exception: bool) -> Span | None:
    opens = _parse_time(entry.get("startTime"))
    closes = _parse_time(entry.get("endTime"))
    if opens is None or closes is None:
        return None
    # A close time at or before the open time means the span runs past midnight.
    crosses = closes <= opens
    return Span(
        service_date=day,
        opens_at=opens,
        closes_at=closes,
        closes_next_day=crosses,
        menu_types=tuple(entry.get("menuTypes") or ()),
        source_event_id=entry.get("id") if not is_exception else entry.get("id"),
        is_exception=is_exception,
    )


def resolve_day(events: list[dict], day: date) -> list[Span]:
    """Resolve one location's events into concrete spans for one date.

    An exception that matches the date replaces its parent event's span for
    that date. An exception with open=false closes the location outright.
    """
    spans: list[Span] = []

    for event in events or []:
        exceptions = [e for e in (event.get("exceptions") or []) if _covers(e, day)]

        if exceptions:
            for exception in exceptions:
                # open=false is a closure, so the parent span is dropped and
                # nothing replaces it.
                if exception.get("open") is False:
                    continue
                span = _span_from(exception, day, is_exception=True)
                if span:
                    spans.append(span)
            continue

        if _covers(event, day):
            span = _span_from(event, day, is_exception=False)
            if span:
                spans.append(span)

    return sorted(spans, key=lambda s: (s.opens_at, s.closes_at))


def resolve_range(events: list[dict], start: date, days: int) -> list[Span]:
    """Resolve a contiguous window of dates. Used by the scraper to fill cache."""
    out: list[Span] = []
    for offset in range(days):
        out.extend(resolve_day(events, start + timedelta(days=offset)))
    return out


def open_state(spans_by_date: dict[date, list[Span]], moment: datetime) -> OpenState:
    """Derive open/closed plus the next transition from resolved spans.

    Yesterday's spans are considered too, because an overnight span that opened
    yesterday can still be running now.
    """
    today = moment.date()
    yesterday = today - timedelta(days=1)

    candidates: list[Span] = []
    for day in (yesterday, today):
        candidates.extend(spans_by_date.get(day, []))

    for span in candidates:
        if span.contains(moment):
            return OpenState(
                is_open=True,
                opens_at=span.start_dt(),
                closes_at=span.end_dt(),
                next_transition=span.end_dt(),
                spans_today=spans_by_date.get(today, []),
            )

    # Closed. Find the next opening across the cached window.
    upcoming = sorted(
        (s for spans in spans_by_date.values() for s in spans if s.start_dt() > moment),
        key=lambda s: s.start_dt(),
    )
    nxt = upcoming[0].start_dt() if upcoming else None
    return OpenState(
        is_open=False,
        opens_at=nxt,
        closes_at=None,
        next_transition=nxt,
        spans_today=spans_by_date.get(today, []),
    )


def span_from_row(row: dict) -> Span:
    """Rebuild a Span from a cached dining_hours row."""
    return Span(
        service_date=date.fromisoformat(row["service_date"]),
        opens_at=time.fromisoformat(row["opens_at"]),
        closes_at=time.fromisoformat(row["closes_at"]),
        closes_next_day=bool(row["closes_next_day"]),
        menu_types=tuple(filter(None, (row.get("menu_types") or "").split(","))),
        source_event_id=row.get("source_event_id"),
        is_exception=bool(row.get("is_exception")),
    )


def group_by_date(rows: list[dict]) -> dict[date, list[Span]]:
    """Group cached hours rows into the shape open_state expects."""
    grouped: dict[date, list[Span]] = {}
    for row in rows:
        span = span_from_row(row)
        grouped.setdefault(span.service_date, []).append(span)
    return grouped
