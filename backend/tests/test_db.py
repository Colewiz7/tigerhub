"""Migration runner and model round trips."""

from datetime import date, time

from app import db
from app.hours import Span
from app.models import dining, events, health, makerspace, occupancy


def test_migrations_are_idempotent(temp_db):
    # temp_db already migrated once, so a second run must be a no-op.
    assert db.migrate() == []
    rows = db.connection().execute("SELECT version FROM schema_version").fetchall()
    assert [r["version"] for r in rows] == [
        "001_initial",
        "002_occupancy_probe",
        "003_recreation",
    ]


def test_dining_round_trip(temp_db):
    dining.replace_locations([{
        "id": 23, "name": "Crossroads", "summary": "s", "description": "d",
        "maps_url": "u", "department": "Dining", "mdo_id": 123,
    }])
    spans = [Span(date(2026, 8, 28), time(10, 30), time(18, 0), menu_types=("LUNCH",))]
    dining.replace_hours(23, spans, (date(2026, 8, 28), date(2026, 9, 10)))

    assert len(dining.list_locations()) == 1
    rows = dining.hours_between(date(2026, 8, 28), date(2026, 8, 28))
    assert rows[0]["opens_at"] == "10:30:00"
    assert rows[0]["menu_types"] == "LUNCH"


def test_replace_hours_clears_the_window(temp_db):
    dining.replace_locations([{
        "id": 1, "name": "X", "summary": None, "description": None,
        "maps_url": None, "department": None, "mdo_id": None,
    }])
    window = (date(2026, 8, 28), date(2026, 8, 29))
    dining.replace_hours(1, [Span(date(2026, 8, 28), time(9, 0), time(17, 0))], window)
    dining.replace_hours(1, [Span(date(2026, 8, 29), time(9, 0), time(17, 0))], window)
    rows = dining.hours_between(*window)
    assert len(rows) == 1
    assert rows[0]["service_date"] == "2026-08-29"


def test_events_upsert_and_filter(temp_db):
    base = {
        "description": None, "location": None, "building": None, "room": None,
        "event_type": None, "url": None, "ends_at": None, "all_day": 0,
    }
    events.upsert_many([
        {**base, "uid": "a", "source": "campusgroups", "title": "Club thing",
         "organizer": "RIT FoodShare", "organizer_key": "FOODSHARE",
         "starts_at": "2026-09-01T10:00:00-04:00"},
        {**base, "uid": "b", "source": "drupal", "title": "Official thing",
         "organizer": "RIT", "organizer_key": "RIT",
         "starts_at": "2026-09-01T12:00:00-04:00"},
    ])
    from datetime import datetime, timezone
    start = datetime(2026, 8, 1, tzinfo=timezone.utc)
    end = datetime(2026, 10, 1, tzinfo=timezone.utc)

    assert len(events.query(start, end)) == 2
    assert len(events.query(start, end, sources=["drupal"])) == 1
    assert len(events.query(start, end, organizer_keys=["FOODSHARE"])) == 1
    # Muting a noisy organizer is the FoodShare case.
    muted = events.query(start, end, exclude_organizer_keys=["FOODSHARE"])
    assert len(muted) == 1 and muted[0]["uid"] == "b"


def test_events_same_uid_across_sources_coexist(temp_db):
    """No dedupe for MVP, so the overlap stays observable."""
    base = {
        "description": None, "location": None, "building": None, "room": None,
        "organizer": None, "organizer_key": None, "event_type": None, "url": None,
        "ends_at": None, "all_day": 0, "starts_at": "2026-09-01T10:00:00-04:00",
    }
    events.upsert_many([
        {**base, "uid": "same", "source": "campusgroups", "title": "A"},
        {**base, "uid": "same", "source": "drupal", "title": "B"},
    ])
    from datetime import datetime, timezone
    rows = events.query(datetime(2026, 8, 1, tzinfo=timezone.utc),
                        datetime(2026, 10, 1, tzinfo=timezone.utc))
    assert len(rows) == 2


def test_events_prune_keeps_cache_when_fetch_is_empty(temp_db):
    base = {
        "description": None, "location": None, "building": None, "room": None,
        "organizer": None, "organizer_key": None, "event_type": None, "url": None,
        "ends_at": None, "all_day": 0, "starts_at": "2026-09-01T10:00:00-04:00",
    }
    events.upsert_many([{**base, "uid": "a", "source": "drupal", "title": "A"}])
    assert events.prune_source("drupal", []) == 0
    from datetime import datetime, timezone
    assert len(events.query(datetime(2026, 8, 1, tzinfo=timezone.utc),
                            datetime(2026, 10, 1, tzinfo=timezone.utc))) == 1


def test_makerspace_replace_all(temp_db):
    makerspace.replace_all([
        {"id": "1", "name": "CNC", "sub_name": None, "room": "Wood Shop",
         "in_use": 0, "num_available": 1, "num_in_use": 0},
    ])
    assert len(makerspace.list_equipment()) == 1
    makerspace.replace_all([
        {"id": "2", "name": "Laser", "sub_name": None, "room": "Laser Cutting",
         "in_use": 1, "num_available": 0, "num_in_use": 1},
    ])
    items = makerspace.list_equipment()
    assert len(items) == 1 and items[0]["id"] == "2"
    assert makerspace.room_summary()[0]["room"] == "Laser Cutting"


def test_occupancy_round_trip(temp_db):
    occupancy.upsert({
        "mdo_id": 123, "count": 152, "max_occ": 150, "open_status": "Open Now",
        "hourly": [{"hour": 0, "today": 4}],
    })
    reading = occupancy.get(123)
    assert reading["count"] == 152
    assert reading["hourly"][0]["hour"] == 0
    assert occupancy.get(999) is None


def test_health_records_success_and_failure(temp_db):
    health.record_failure("dining", "boom")
    health.record_failure("dining", "boom again")
    row = health.all_sources()[0]
    assert row["consecutive_failures"] == 2
    assert row["last_error"] == "boom again"

    health.record_success("dining", 24)
    row = health.all_sources()[0]
    assert row["consecutive_failures"] == 0
    assert row["last_record_count"] == 24
    # The old error is kept for context, but failures reset.
    assert row["last_success_at"] is not None


def test_occupancy_probe_narrows_polling(temp_db):
    """Only 5 of 24 locations publish occupancy, so the rest must not be
    polled every cycle."""
    dining.replace_locations([
        {"id": i, "name": f"L{i}", "summary": None, "description": None,
         "maps_url": None, "department": "Dining", "mdo_id": 100 + i}
        for i in range(4)
    ])
    # Nothing probed yet, so everything is due.
    assert len(occupancy.due_for_poll(360)) == 4

    occupancy.record_probe(100, has_density=True)
    occupancy.record_probe(101, has_density=False)
    occupancy.record_probe(102, has_density=False)
    occupancy.record_probe(103, has_density=False)

    # The sensor location stays in every cycle, the other three drop out.
    assert occupancy.due_for_poll(360) == [100]
    # With a zero minute reprobe window, the others come back for a recheck.
    assert len(occupancy.due_for_poll(0)) == 4
