"""TigerCenter dining: locations, hours, visiting chefs.

Endpoint: https://tigercenter.rit.edu/tigerCenterApi/tc/dining-all?date=YYYY-MM-DD
No auth, no cookies, no custom headers. Verified 2026-08-28.

Everything under the TCAuth base (/tigerCenterApi/login_shib/tc/) is login gated
and is deliberately never touched.

This one payload carries three things we need: location metadata, the hours
recurrence model, and menus[] where category == "Visiting Chef".
"""

import logging
from datetime import date, timedelta

from app import http
from app.hours import resolve_day
from app.models import dining
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "tigercenter_dining"
BASE_URL = "https://tigercenter.rit.edu/tigerCenterApi/tc/dining-all"

# How far ahead to resolve concrete hours. Two weeks covers the client's
# calendar view without bloating the cache.
HORIZON_DAYS = 14


async def fetch(day: date) -> dict:
    return await http.get_json(BASE_URL, params={"date": day.isoformat()})


def parse(payload: dict) -> list[dict]:
    """Normalize the raw payload into location dicts, keeping raw events."""
    out = []
    for loc in payload.get("locations") or []:
        out.append(
            {
                "id": loc["id"],
                "name": loc.get("name") or "",
                "summary": loc.get("summary"),
                "description": loc.get("description"),
                "maps_url": loc.get("mapsUrl"),
                "department": loc.get("department"),
                "mdo_id": loc.get("mdoId"),
                "events": loc.get("events") or [],
                "menus": loc.get("menus") or [],
            }
        )
    return out


async def scrape() -> int:
    today = date.today()
    payload = await fetch(today)
    locations = parse(payload)
    if not locations:
        raise ValueError("dining-all returned zero locations")

    dining.replace_locations(
        [{k: v for k, v in loc.items() if k not in ("events", "menus")} for loc in locations]
    )

    window = (today, today + timedelta(days=HORIZON_DAYS - 1))
    for loc in locations:
        spans = []
        for offset in range(HORIZON_DAYS):
            spans.extend(resolve_day(loc["events"], today + timedelta(days=offset)))
        dining.replace_hours(loc["id"], spans, window)

        # menus[] on this payload is for the requested date only.
        dining.replace_menu_items(loc["id"], today, loc["menus"])

    return len(locations)


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
