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


def test_health_sources_reports_503_when_nothing_has_run(client):
    response = client.get("/health/sources")
    assert response.status_code == 503
    assert response.json()["all_healthy"] is False


def test_health_sources_reports_error_and_stale_config(client):
    health.record_failure("tigercenter_dining", "parser exploded")
    body = client.get("/health/sources").json()
    entry = next(s for s in body["sources"] if s["source"] == "tigercenter_dining")
    assert entry["last_error"] == "parser exploded"
    assert entry["healthy"] is False
    # Residence halls ship unverified, so they must be flagged here.
    assert any(e["kind"] == "residence_hall" for e in body["stale_config"])


def test_health_sources_healthy_after_success(client):
    for source in ["tigercenter_dining", "campusgroups", "drupal",
                   "makerspace_equipment", "maps_occupancy"]:
        health.record_success(source, 1)
    response = client.get("/health/sources")
    assert response.status_code == 200
    assert response.json()["all_healthy"] is True


def test_dining_list_and_open_now(client):
    _seed_open_location()
    body = client.get("/dining").json()
    assert len(body) == 1
    assert body[0]["is_open"] is True
    assert body[0]["closes_at"] is not None
    assert client.get("/dining", params={"open_now": True}).json()


def test_dining_includes_occupancy_when_present(client):
    _seed_open_location()
    occupancy.upsert({"mdo_id": 123, "count": 75, "max_occ": 150,
                      "open_status": "Open Now", "hourly": []})
    body = client.get("/dining").json()
    assert body[0]["occupancy"]["percent_full"] == 50


def test_dining_omits_occupancy_when_missing(client):
    """A failed occupancy parse hides the chip, it does not break dining."""
    _seed_open_location()
    body = client.get("/dining").json()
    assert body[0]["occupancy"] is None


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
    assert len(chefs) == 1
    assert chefs[0]["name"] == "D'Mangu"
    assert len(client.get("/dining/specials").json()) == 2


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
    assert len(client.get("/events").json()) == 2
    assert len(client.get("/events", params={"source": "drupal"}).json()) == 1
    assert len(client.get("/events", params={"mute": "FOODSHARE"}).json()) == 1
    organizers = client.get("/events/organizers").json()
    assert {o["organizer_key"] for o in organizers} == {"FOODSHARE", "RIT"}


def test_makerspace_routes(client):
    makerspace.replace_all([
        {"id": "1", "name": "CNC Router", "sub_name": "Shopsabre", "room": "Wood Shop",
         "in_use": 0, "num_available": 1, "num_in_use": 0},
    ])
    assert client.get("/makerspace/equipment").json()[0]["name"] == "CNC Router"
    assert client.get("/makerspace/rooms").json()[0]["room"] == "Wood Shop"
    # Hours come from static config, not their broken feed.
    assert client.get("/makerspace/hours").json()[0]["location"] == "SHED-1330"


def test_housing_address_lookup(client):
    halls = client.get("/housing/halls").json()
    assert any(h["id"] == "global-village" for h in halls)

    body = client.get("/housing/halls/global-village/address",
                      params={"name": "Cole"}).json()
    assert body["lines"][0] == "Cole"
    assert body["post_office"]["id"] == "global-village"
    # Addresses are unverified placeholders until a human confirms them.
    assert body["verified"] is False

    assert client.get("/housing/halls/nope/address").status_code == 404


def test_post_offices(client):
    body = client.get("/post-offices").json()
    ids = {o["id"] for o in body}
    assert ids == {"global-village", "perry-hall"}
