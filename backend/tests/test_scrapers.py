"""Parser tests against saved real responses. No network."""

from datetime import date

import pytest

from app.scrapers import campusgroups, drupal_events, makerspace, maps_occupancy, tigercenter
from tests.conftest import fixture_bytes, fixture_json, fixture_text


def test_tigercenter_parse_shape():
    locations = tigercenter.parse(fixture_json("tigercenter_dining_all.json"))
    assert len(locations) == 24
    crossroads = next(l for l in locations if l["id"] == 23)
    assert crossroads["name"] == "The Cafe & Market at Crossroads"
    assert crossroads["mdo_id"] == 123
    assert crossroads["events"]


def test_tigercenter_surfaces_visiting_chefs():
    """Visiting chefs come free from this payload, no separate scraper."""
    locations = tigercenter.parse(fixture_json("tigercenter_dining_all.json"))
    chefs = [
        (loc["name"], menu["name"])
        for loc in locations
        for menu in loc["menus"]
        if menu.get("category") == "Visiting Chef"
    ]
    assert chefs, "expected at least one visiting chef in the fixture"


def test_tigercenter_parse_tolerates_empty_payload():
    assert tigercenter.parse({}) == []
    assert tigercenter.parse({"locations": []}) == []


def test_campusgroups_parse():
    parsed = campusgroups.parse(fixture_bytes("campusgroups_rit.ics"))
    assert parsed
    first = parsed[0]
    assert first["source"] == "campusgroups"
    assert first["uid"]
    assert first["title"]
    assert first["starts_at"]


def test_campusgroups_extracts_organizer_and_acronym():
    parsed = campusgroups.parse(fixture_bytes("campusgroups_rit.ics"))
    withorg = [e for e in parsed if e["organizer"]]
    assert withorg, "organizer is present on 100% of real events"
    keyed = [e for e in parsed if e["organizer_key"]]
    assert keyed, "club_acronym drives grouping and muting, it must survive parsing"
    assert all(e["organizer_key"] == e["organizer_key"].upper() for e in keyed)


def test_campusgroups_timestamps_are_timezone_aware():
    parsed = campusgroups.parse(fixture_bytes("campusgroups_rit.ics"))
    for event in parsed:
        assert "+" in event["starts_at"] or "Z" in event["starts_at"]


def test_drupal_parse():
    payload = fixture_json("drupal_events.json")
    parsed = drupal_events.parse(payload["data"])
    assert parsed
    for event in parsed:
        assert event["source"] == "drupal"
        assert event["uid"]
        assert event["starts_at"]


def test_drupal_combines_split_date_and_time():
    stamp, all_day = drupal_events._combine("2026-09-01", "14:30:00")
    assert stamp.startswith("2026-09-01T14:30")
    assert all_day is False

    stamp, all_day = drupal_events._combine("2026-09-01", None)
    assert all_day is True

    assert drupal_events._combine(None, "14:30:00") == (None, False)


def test_makerspace_parse_and_archived_filter():
    parsed = makerspace.parse(fixture_json("makerspace_equipments.json"))
    assert parsed
    assert all(isinstance(item["id"], str) for item in parsed)
    assert all("archived" not in item for item in parsed)
    rooms = {item["room"] for item in parsed}
    assert len(rooms) > 1


def test_makerspace_parse_raises_on_graphql_errors():
    with pytest.raises(ValueError, match="GraphQL errors"):
        makerspace.parse({"errors": [{"message": "nope"}]})
    with pytest.raises(ValueError, match="no data.equipments"):
        makerspace.parse({"data": {}})


def test_occupancy_extracts_density_from_turbo_stream():
    raw = fixture_text("maps_details_123.data")
    reading = maps_occupancy.parse(raw, 123)
    assert reading is not None
    assert reading["mdo_id"] == 123
    assert isinstance(reading["count"], int)
    assert isinstance(reading["max_occ"], int)
    assert reading["open_status"]
    assert len(reading["hourly"]) == 24
    assert {"hour", "today", "one_week_ago", "average"} <= set(reading["hourly"][0])


def test_occupancy_returns_none_instead_of_raising_on_garbage():
    """A format change must hide the chip, not break the dining response."""
    assert maps_occupancy.extract("") is None
    assert maps_occupancy.extract("not json at all") is None
    assert maps_occupancy.extract('{"not":"an array"}') is None
    assert maps_occupancy.extract('["no density key here"]') is None
    assert maps_occupancy.parse("garbage", 123) is None


def test_occupancy_locations_without_sensors_are_not_an_error():
    """19 of 24 dining locations have no densityData key upstream. That is
    normal, not a parse failure."""
    payload = '["routes/home",{"_0":1},"something else"]'
    assert maps_occupancy.extract(payload) is None


def test_campusgroups_strips_placeholder_locations():
    """CampusGroups puts UI prompts in LOCATION. They are not addresses and
    must never reach the client."""
    from app.scrapers.campusgroups import clean_location

    assert clean_location("Sign in to download the location") is None
    assert clean_location("TBA") is None
    assert clean_location("To be announced") is None
    assert clean_location("") is None
    assert clean_location(None) is None
    assert clean_location("   ") is None


def test_campusgroups_truncates_a_postal_address_to_the_venue():
    from app.scrapers.campusgroups import clean_location

    assert (
        clean_location(
            "RIT FoodShare (113 Riverknoll), 113 Riverknoll, "
            "Rochester, NY 14623, United States"
        )
        == "RIT FoodShare (113 Riverknoll)"
    )
    # A venue with no address attached survives untouched.
    assert clean_location("Global Village") == "Global Village"
    assert (
        clean_location("NTID Dance Lab 1 & 2 (LBJ-1845 & 1825)")
        == "NTID Dance Lab 1 & 2 (LBJ-1845 & 1825)"
    )


def test_campusgroups_real_feed_has_no_placeholder_locations():
    parsed = campusgroups.parse(fixture_bytes("campusgroups_rit.ics"))
    for event in parsed:
        location = event["location"]
        if location is None:
            continue
        assert "sign in" not in location.lower()
        assert "," not in location, f"postal address leaked through: {location}"


def test_recreation_parses_every_facility_and_all_seven_days():
    from datetime import date

    from app.scrapers import recreation

    rows = recreation.parse(
        fixture_text("recreation_facility_hours.html"), today=date(2026, 8, 29)
    )
    facilities = {row["facility"] for row in rows}
    assert "Judson/Hale Aquatics Center" in facilities
    assert "Wiedman Fitness Center" in facilities
    assert len(facilities) >= 5

    # The page publishes a rolling seven days. The header row runs into the
    # first data row in this markup, which used to swallow today entirely.
    slc = [r for r in rows if r["facility"].startswith("Hale-Andrews Student")]
    assert len({r["service_date"] for r in slc}) == 7
    assert any(r["service_date"] == "2026-08-29" for r in slc), "today was dropped"


def test_recreation_splits_a_multi_session_day():
    """The pool runs a morning, lunch and evening block. Collapsing those into
    one range would say the pool is open when it is not."""
    from datetime import date

    from app.scrapers import recreation

    rows = recreation.parse(
        fixture_text("recreation_facility_hours.html"), today=date(2026, 8, 29)
    )
    monday = [
        r
        for r in rows
        if "Aquatics" in r["facility"] and r["service_date"] == "2026-08-31"
    ]
    assert len(monday) == 3
    assert [(r["opens_at"], r["closes_at"]) for r in monday] == [
        ("06:45", "08:45"),
        ("12:00", "13:45"),
        ("19:00", "22:00"),
    ]


def test_recreation_records_closed_days():
    from datetime import date

    from app.scrapers import recreation

    rows = recreation.parse(
        fixture_text("recreation_facility_hours.html"), today=date(2026, 8, 29)
    )
    closed = [r for r in rows if r["closed"]]
    assert closed, "the SLC Main Office is closed at weekends"
    assert all(r["opens_at"] is None for r in closed)


def test_recreation_time_parsing():
    from app.scrapers.recreation import parse_time

    assert parse_time("10am") == "10:00"
    assert parse_time("6:45am") == "06:45"
    assert parse_time("12pm") == "12:00"
    assert parse_time("11pm") == "23:00"
    assert parse_time("12am") == "00:00"
    assert parse_time("noon") == "12:00"
    assert parse_time("nonsense") is None


def test_recreation_hours_cell_parsing():
    from app.scrapers.recreation import parse_hours_cell

    assert parse_hours_cell("CLOSED") == []
    assert parse_hours_cell("") == []
    assert parse_hours_cell("10am - 11pm") == [
        {"opens_at": "10:00", "closes_at": "23:00"}
    ]
    assert len(parse_hours_cell("6:45am - 8:45am, 12pm - 1:45pm, 7pm - 10pm")) == 3
