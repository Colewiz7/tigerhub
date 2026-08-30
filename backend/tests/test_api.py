"""Route tests. The app is exercised against a seeded cache, never the network."""

from datetime import date, datetime, time, timedelta

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import settings
from app.api import campus, dining as dining_routes, events as events_routes, health as health_routes, makerspace as makerspace_routes
from app.hours import Span
from app.models import dining, events, health, makerspace, occupancy


@pytest.fixture
def client(temp_db, config):
    """A router-only app, so the scheduler and startup scrape never run."""
    app = FastAPI()
    app.include_router(health_routes.router)
    app.include_router(dining_routes.router)
    app.include_router(events_routes.router)
    app.include_router(makerspace_routes.router)
    app.include_router(campus.router)
    return TestClient(app)


def _seed_open_location():
    now = datetime.now(settings.CAMPUS_TZ)
    dining.replace_locations([{
        "id": 23, "name": "Crossroads", "summary": "Cafe", "description": None,
        "maps_url": None, "department": "Dining", "mdo_id": 123,
    }])
    # A span covering the current moment, so is_open is deterministic.
    span = Span(now.date(), time(0, 0), time(23, 59, 59))
    dining.replace_hours(23, [span], (now.date(), now.date()))
    return now


def test_health(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert "Not affiliated" in body["disclaimer"]


def test_health_answers_before_any_scrape_completes(client):
    """A cold cache is not an error state, so liveness must not depend on it."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_cold_cache_is_priming_not_failing(client):
    body = client.get("/health/sources").json()
    assert body["priming"] is True
    assert body["all_healthy"] is True
    assert {s["state"] for s in body["sources"]} == {"priming"}
    assert client.get("/health/sources").status_code == 200


def test_cold_data_endpoints_return_200_and_stale(client):
    """Empty arrays with stale: true, never a 503."""
    for path in ["/dining", "/events", "/makerspace/equipment",
                 "/dining/visiting-chefs", "/events/organizers"]:
        response = client.get(path)
        assert response.status_code == 200, path
        body = response.json()
        assert body["data"] == [], path
        assert body["stale"] is True, path


def test_health_sources_reports_a_broken_parser(client, monkeypatch):
    from datetime import timedelta
    from app import freshness
    # Push the boot time back so the priming grace has expired.
    monkeypatch.setattr(freshness, "STARTED_AT",
                        freshness.STARTED_AT - timedelta(hours=1))
    health.record_failure("tigercenter_dining", "parser exploded")
    response = client.get("/health/sources")
    assert response.status_code == 503
    entry = next(s for s in response.json()["sources"]
                 if s["source"] == "tigercenter_dining")
    assert entry["last_error"] == "parser exploded"
    assert entry["state"] == "failing"
    assert entry["healthy"] is False


def test_health_sources_healthy_after_success(client):
    for source in ["tigercenter_dining", "campusgroups", "drupal",
                   "makerspace_equipment", "maps_occupancy", "recreation_hours",
                   "fd_menus", "athletics", "campus_places"]:
        health.record_success(source, 1)
    response = client.get("/health/sources")
    assert response.status_code == 200
    body = response.json()
    assert body["all_healthy"] is True
    assert body["priming"] is False
    assert {s["state"] for s in body["sources"]} == {"ok"}


def test_data_is_not_stale_after_a_successful_scrape(client):
    _seed_open_location()
    health.record_success("tigercenter_dining", 24)
    body = client.get("/dining").json()
    assert body["stale"] is False
    assert body["last_updated"] is not None


def test_dining_list_and_open_now(client):
    _seed_open_location()
    body = client.get("/dining").json()
    assert len(body["data"]) == 1
    assert body["data"][0]["is_open"] is True
    assert body["data"][0]["closes_at"] is not None
    assert client.get("/dining", params={"open_now": True}).json()["data"]


def test_dining_includes_occupancy_when_present(client):
    _seed_open_location()
    occupancy.upsert({"mdo_id": 123, "count": 75, "max_occ": 150,
                      "open_status": "Open Now", "hourly": []})
    body = client.get("/dining").json()
    assert body["data"][0]["occupancy"]["percent_full"] == 50


def test_dining_omits_occupancy_when_missing(client):
    """A failed occupancy parse hides the chip, it does not break dining."""
    _seed_open_location()
    body = client.get("/dining").json()
    assert body["data"][0]["occupancy"] is None


def test_dining_detail_and_404(client):
    _seed_open_location()
    assert client.get("/dining/23").json()["name"] == "Crossroads"
    assert client.get("/dining/999").status_code == 404


def test_visiting_chefs(client):
    _seed_open_location()
    today = datetime.now(settings.CAMPUS_TZ).date()
    dining.replace_menu_items(23, today, [
        {"id": 150, "name": "D'Mangu", "description": "Dominican",
         "price": 0, "category": "Visiting Chef"},
        {"id": 151, "name": "Soup", "description": None, "price": 0, "category": "Daily"},
    ])
    chefs = client.get("/dining/visiting-chefs").json()
    assert len(chefs["data"]) == 1
    assert chefs["data"][0]["name"] == "D'Mangu"
    assert len(client.get("/dining/specials").json()["data"]) == 2


def test_events_filtering_and_organizers(client):
    start = datetime.now(settings.CAMPUS_TZ) + timedelta(hours=1)
    base = {"description": None, "location": None, "building": None, "room": None,
            "event_type": None, "url": None, "ends_at": None, "all_day": 0,
            "starts_at": start.isoformat()}
    events.upsert_many([
        {**base, "uid": "a", "source": "campusgroups", "title": "Club",
         "organizer": "RIT FoodShare", "organizer_key": "FOODSHARE"},
        {**base, "uid": "b", "source": "drupal", "title": "Official",
         "organizer": "RIT", "organizer_key": "RIT"},
    ])
    assert len(client.get("/events").json()["data"]) == 2
    assert len(client.get("/events", params={"source": "drupal"}).json()["data"]) == 1
    assert len(client.get("/events", params={"mute": "FOODSHARE"}).json()["data"]) == 1
    organizers = client.get("/events/organizers").json()["data"]
    assert {o["organizer_key"] for o in organizers} == {"FOODSHARE", "RIT"}


def test_makerspace_routes(client):
    makerspace.replace_all([
        {"id": "1", "name": "CNC Router", "sub_name": "Shopsabre", "room": "Wood Shop",
         "in_use": 0, "num_available": 1, "num_in_use": 0},
    ])
    assert client.get("/makerspace/equipment").json()["data"][0]["name"] == "CNC Router"
    assert client.get("/makerspace/rooms").json()["data"][0]["room"] == "Wood Shop"
    # Hours come from static config, not their broken feed.
    assert client.get("/makerspace/hours").json()[0]["location"] == "SHED-1330"


def test_housing_areas_are_zones_not_halls(client):
    areas = client.get("/housing/areas").json()["data"]
    ids = {a["id"] for a in areas}
    assert "residence-halls" in ids
    assert "global-village" in ids
    # The two direct delivery locations are listed and flagged.
    assert {"rit-inn", "175-jefferson"} <= ids
    assert next(a for a in areas if a["id"] == "rit-inn")["direct_delivery"] is True


def test_housing_address_matches_published_example(client):
    body = client.get("/housing/areas/global-village/address",
                      params={"name": "Justin Case", "unit": "GV 400 1020"}).json()
    assert body["lines"] == [
        "Justin Case", "GV 400 1020", "6000 Reynolds Drive", "Rochester NY 14623",
    ]
    assert body["post_office"]["id"] == "global-village"
    assert body["unit_supplied"] is True
    # Now sourced from the authoritative RIT page, so this is verified.
    assert body["verified"] is True


def test_housing_address_without_unit_shows_the_format(client):
    body = client.get("/housing/areas/riverknoll/address", params={"name": "Cole"}).json()
    assert body["lines"][1] == "RK Apartment #"
    assert body["unit_supplied"] is False
    assert body["line2_example"] == "RK 123"


def test_direct_delivery_address_has_no_post_office(client):
    body = client.get("/housing/areas/rit-inn/address", params={"name": "Cole"}).json()
    assert body["direct_delivery"] is True
    assert body["post_office"] is None
    assert "Henrietta" in body["lines"][-1]


def test_unknown_area_404(client):
    assert client.get("/housing/areas/nope/address").status_code == 404


def test_post_offices(client):
    body = client.get("/post-offices").json()["data"]
    ids = {o["id"] for o in body}
    assert ids == {"global-village", "dsp"}
    streets = {o["id"]: o["street"] for o in body}
    assert streets["global-village"] == "6000 Reynolds Drive"
    assert streets["dsp"] == "43 Greenleaf Court"


def test_occupancy_over_capacity_is_flagged(client):
    """RIT's max_occ is often too low. The count exceeding it is a fact the
    API reports, so the client can avoid quoting a precise percentage."""
    _seed_open_location()
    occupancy.upsert({"mdo_id": 123, "count": 46, "max_occ": 38,
                      "open_status": "Open Now", "hourly": []})
    occ = client.get("/dining").json()["data"][0]["occupancy"]
    assert occ["over_capacity"] is True
    assert occ["percent_full"] == 100


def test_occupancy_under_capacity_is_not_flagged(client):
    _seed_open_location()
    occupancy.upsert({"mdo_id": 123, "count": 9, "max_occ": 12,
                      "open_status": "Open Now", "hourly": []})
    occ = client.get("/dining").json()["data"][0]["occupancy"]
    assert occ["over_capacity"] is False
    assert occ["percent_full"] == 75


def test_occupancy_without_a_denominator_still_shows_the_count(client):
    """A missing max_occ must not silently hide the location."""
    _seed_open_location()
    occupancy.upsert({"mdo_id": 123, "count": 235, "max_occ": None,
                      "open_status": "Open Now", "hourly": []})
    occ = client.get("/dining").json()["data"][0]["occupancy"]
    assert occ is not None, "a count with no capacity must still return a chip"
    assert occ["count"] == 235
    assert occ["percent_full"] is None
    assert occ["over_capacity"] is False
