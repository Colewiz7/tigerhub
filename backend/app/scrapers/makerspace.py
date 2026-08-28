"""SHED makerspace real time equipment availability.

Endpoint: POST https://make.rit.edu/graphql, no auth. Verified 2026-08-28,
56 machines across 10 rooms.

Equipment availability only. Their `makerspaces { hours }` query is deliberately
not used: it returns closed:true on every row with an ISO timestamp where a
weekday belongs, which is a bug in their data. SHED hours are hardcoded in
app/config/data/shed_hours.json instead.

Introspection is disabled in production, so this query was built from their
open source schema at rit-construct-makerspace/access-control-server.
"""

import logging

from app import http
from app.models import makerspace as makerspace_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "makerspace_equipment"
GRAPHQL_URL = "https://make.rit.edu/graphql"

# `equipments` excludes archived items. `allEquipment` includes them, so it is
# the wrong query for an availability view.
QUERY = """
{
  equipments {
    id
    name
    subName
    inUse
    numAvailable
    numInUse
    archived
    room { id name }
  }
}
"""


async def fetch() -> dict:
    return await http.post_json(GRAPHQL_URL, {"query": QUERY})


def parse(payload: dict) -> list[dict]:
    if payload.get("errors"):
        raise ValueError(f"GraphQL errors: {payload['errors']}")

    items = (payload.get("data") or {}).get("equipments")
    if items is None:
        raise ValueError("GraphQL response had no data.equipments")

    out = []
    for item in items:
        if item.get("archived"):
            continue
        room = item.get("room") or {}
        out.append(
            {
                "id": str(item["id"]),
                "name": item.get("name") or "",
                "sub_name": (item.get("subName") or "").strip() or None,
                "room": room.get("name"),
                "in_use": int(bool(item.get("inUse"))),
                "num_available": item.get("numAvailable") or 0,
                "num_in_use": item.get("numInUse") or 0,
            }
        )
    return out


async def scrape() -> int:
    parsed = parse(await fetch())
    if not parsed:
        raise ValueError("makerspace returned zero equipment rows")
    makerspace_model.replace_all(parsed)
    return len(parsed)


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
