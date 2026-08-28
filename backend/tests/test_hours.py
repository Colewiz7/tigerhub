"""The recurrence resolution is the only real logic in the app, so it gets the
most tests. Cases are built from the real TigerCenter payload."""

from datetime import date, datetime, time

import pytest

from app import settings
from app.hours import Span, group_by_date, open_state, resolve_day
from tests.conftest import fixture_json


@pytest.fixture
def payload():
    return fixture_json("tigercenter_dining_all.json")


def _location(payload, name):
    return next(loc for loc in payload["locations"] if loc["name"] == name)


def test_weekday_window_resolves(payload):
    crossroads = _location(payload, "The Cafe & Market at Crossroads")
    # 2026-08-31 is a Monday inside the Fall 2026 window.
    spans = resolve_day(crossroads["events"], date(2026, 8, 31))
    assert spans, "expected Crossroads to be open on a Monday in the term"
    assert all(s.service_date == date(2026, 8, 31) for s in spans)


def test_weekend_outside_days_of_week_is_closed(payload):
    crossroads = _location(payload, "The Cafe & Market at Crossroads")
    event = crossroads["events"][0]
    assert "SUNDAY" not in event["daysOfWeek"]
    # 2026-08-30 is a Sunday, and there is no exception for it.
    spans = [s for s in resolve_day([event], date(2026, 8, 30)) if not s.is_exception]
    assert spans == []


def test_date_outside_term_window_is_closed(payload):
    crossroads = _location(payload, "The Cafe & Market at Crossroads")
    # Well before startDate 2026-08-16.
    assert resolve_day(crossroads["events"], date(2026, 1, 5)) == []


def test_exception_overrides_the_base_span():
    event = {
        "id": 1,
        "startTime": "10:30:00",
        "endTime": "21:00:00",
        "startDate": "2026-08-16",
        "endDate": "2026-12-24",
        "daysOfWeek": ["THURSDAY"],
        "menuTypes": ["LUNCH"],
        "exceptions": [
            {
                "id": 2,
                "startTime": "10:30:00",
                "endTime": "18:00:00",
                "startDate": "2026-08-28",
                "endDate": "2026-08-28",
                "daysOfWeek": ["FRIDAY"],
                "open": True,
            }
        ],
    }
    # 2026-08-28 is a Friday, which the exception covers.
    spans = resolve_day([event], date(2026, 8, 28))
    assert len(spans) == 1
    assert spans[0].closes_at == time(18, 0)
    assert spans[0].is_exception is True

    # 2026-09-03 is a Thursday with no exception, so the base window applies.
    base = resolve_day([event], date(2026, 9, 3))
    assert len(base) == 1
    assert base[0].closes_at == time(21, 0)
    assert base[0].is_exception is False


def test_exception_marked_closed_removes_the_span():
    event = {
        "id": 1,
        "startTime": "08:00:00",
        "endTime": "17:00:00",
        "startDate": "2026-08-16",
        "endDate": "2026-12-24",
        "daysOfWeek": ["MONDAY"],
        "exceptions": [
            {
                "id": 2,
                "startTime": "08:00:00",
                "endTime": "17:00:00",
                "startDate": "2026-09-07",
                "endDate": "2026-09-07",
                "daysOfWeek": ["MONDAY"],
                "open": False,
            }
        ],
    }
    assert resolve_day([event], date(2026, 9, 7)) == []
    assert len(resolve_day([event], date(2026, 9, 14))) == 1


def test_overnight_span_marks_closes_next_day():
    event = {
        "id": 1,
        "startTime": "19:00:00",
        "endTime": "01:00:00",
        "startDate": "2026-08-16",
        "endDate": "2026-12-24",
        "daysOfWeek": ["FRIDAY"],
        "exceptions": [],
    }
    span = resolve_day([event], date(2026, 8, 28))[0]
    assert span.closes_next_day is True
    assert span.end_dt().date() == date(2026, 8, 29)


def test_open_state_true_inside_a_span():
    span = Span(date(2026, 8, 28), time(10, 30), time(21, 0))
    grouped = {date(2026, 8, 28): [span]}
    moment = datetime(2026, 8, 28, 12, 0, tzinfo=settings.CAMPUS_TZ)
    state = open_state(grouped, moment)
    assert state.is_open is True
    assert state.next_transition == span.end_dt()


def test_open_state_uses_yesterdays_overnight_span():
    span = Span(date(2026, 8, 28), time(19, 0), time(1, 0), closes_next_day=True)
    grouped = {date(2026, 8, 28): [span]}
    # 00:30 the next morning is still inside the overnight span.
    moment = datetime(2026, 8, 29, 0, 30, tzinfo=settings.CAMPUS_TZ)
    assert open_state(grouped, moment).is_open is True


def test_open_state_reports_next_opening_when_closed():
    span = Span(date(2026, 8, 29), time(10, 0), time(14, 0))
    grouped = {date(2026, 8, 29): [span]}
    moment = datetime(2026, 8, 28, 12, 0, tzinfo=settings.CAMPUS_TZ)
    state = open_state(grouped, moment)
    assert state.is_open is False
    assert state.next_transition == span.start_dt()


def test_group_by_date_round_trips_a_cached_row():
    rows = [
        {
            "location_id": 23,
            "service_date": "2026-08-28",
            "opens_at": "10:30:00",
            "closes_at": "18:00:00",
            "closes_next_day": 0,
            "menu_types": "LUNCH",
            "source_event_id": 9684,
            "is_exception": 1,
        }
    ]
    grouped = group_by_date(rows)
    span = grouped[date(2026, 8, 28)][0]
    assert span.menu_types == ("LUNCH",)
    assert span.is_exception is True


def test_every_real_location_resolves_without_error(payload):
    """Smoke test across all 24 live locations, to catch shape surprises."""
    for loc in payload["locations"]:
        for offset in range(14):
            resolve_day(loc["events"], date(2026, 8, 28))
