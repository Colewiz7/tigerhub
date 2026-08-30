"""Campus points of interest from maps.rit.edu.

Answers "where is the nearest water fountain", which is the kind of question
the official map makes surprisingly hard.

Reaching this needed a real turbo-stream decoder, see `app/turbo_stream.py` for
why that reverses an earlier decision. The useful data sits at
`subLocations[].locations[].properties` and carries a building abbreviation, a
floor, a room number and a human note like "Corner of hallway, next to
bathrooms".

The full taxonomy is 11 categories and about 50 sub-categories. Only the ones
students actually need are fetched: the rest are parking tiers, building types
and staff facilities that would be noise.

This is physical infrastructure and changes rarely, so it runs twice a day.
"""

import logging

from app import http
from app.models import places as places_model
from app.scrapers.base import run_scraper
from app.turbo_stream import TurboStreamError, decode, find_all

log = logging.getLogger(__name__)

SOURCE = "campus_places"
URL = "https://maps.rit.edu/categories/{category_id}.data"

# Sub-category id to the key we store it under. Ids came from decoding the
# category tree.
KINDS: dict[int, tuple[str, str]] = {
    270: ("water", "Water fountains"),
    195: ("ev_charge", "EV charging"),
    131: ("blue_light", "Blue light phones"),
    135: ("aed", "Defibrillators"),
    159: ("restroom_all_gender", "All-gender restrooms"),
    171: ("restroom_accessible", "Accessible restrooms"),
    151: ("atm", "ATMs"),
    175: ("changing_table", "Diaper changing stations"),
    139: ("entrance_accessible", "Accessible entrances"),
    123: ("bus_stop", "Bus stops"),
    119: ("bike_rack", "Bike racks"),
    232: ("reload", "Tiger Spend reload stations"),
}

# One request per PARENT category returns every sub it contains, so six
# requests cover all twelve kinds rather than twelve.
PARENTS = [35, 19, 27, 23, 15, 7]


async def fetch(category_id: int) -> str:
    return await http.get_text(URL.format(category_id=category_id))


def parse(raw: str) -> dict[int, list[dict]]:
    """Pull the points out of one parent category payload, keyed by sub id.

    A payload carries every sub-category the parent contains, and each group
    names itself through `menu.id`. Grouping on that rather than on position
    means a reordering upstream cannot silently mix water fountains into ATMs.

    Located by key rather than by a fixed path, because the surrounding route
    structure is RIT's to change and the leaf shape is what matters.
    """
    try:
        decoded = decode(raw)
    except TurboStreamError as exc:
        log.warning("could not decode category payload: %s", exc)
        return {}

    out: dict[int, list[dict]] = {}

    for group in find_all(decoded, "subLocations"):
        if not isinstance(group, list):
            continue
        for sub in group:
            if not isinstance(sub, dict):
                continue
            menu = sub.get("menu")
            sub_id = menu.get("id") if isinstance(menu, dict) else None
            if not isinstance(sub_id, int) or sub_id not in KINDS:
                continue

            kind_name = KINDS[sub_id][1]
            places = out.setdefault(sub_id, [])
            seen = {place["id"] for place in places}

            for location in sub.get("locations") or []:
                if not isinstance(location, dict):
                    continue
                props = location.get("properties")
                if not isinstance(props, dict):
                    continue
                place_id = props.get("id")
                name = props.get("name")
                if not isinstance(place_id, int) or not isinstance(name, str):
                    continue
                if place_id in seen:
                    continue
                seen.add(place_id)

                places.append(
                    {
                        "id": place_id,
                        "kind_name": kind_name,
                        "name": name.strip(),
                        "building": (props.get("abbreviation") or "").strip() or None,
                        "building_no": (props.get("buildingNumber") or "").strip() or None,
                        "floor": (props.get("floorLevel") or "").strip() or None,
                        "room": str(props.get("roomNumber") or "").strip() or None,
                        "note": (props.get("descShort") or "").strip() or None,
                        "mdo_id": props.get("mdo_id") if isinstance(props.get("mdo_id"), int) else None,
                    }
                )

    return out


async def scrape() -> int:
    total = 0
    failures: list[int] = []

    # Sequential on purpose. Six categories at roughly 250 KB each is small,
    # but firing them in parallel at someone else's map server is rude.
    for parent in PARENTS:
        try:
            groups = parse(await fetch(parent))
        except Exception as exc:
            log.warning("campus places parent %s failed: %s", parent, exc)
            failures.append(parent)
            continue

        for sub_id, places in groups.items():
            if not places:
                continue
            total += places_model.replace_kind(KINDS[sub_id][0], places)

    if total == 0:
        raise ValueError(f"no campus places parsed, failed parents: {failures}")
    return total


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
