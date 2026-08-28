"""Live occupancy from maps.rit.edu.

maps.rit.edu was rewritten as a Remix app, so the endpoint TigerDine used
(proxySearch/densityMapDetail.php) now 404s. The live data is at
GET https://maps.rit.edu/details/<mdoId>.data in Remix turbo-stream format.

This is a TARGETED extractor, not a general turbo-stream decoder, on purpose.
turbo-stream flattens a value graph into one array where every reference is an
index into that array, and object keys are written as "_<index>". We only need
to walk from the densityData key to its immediate values, so that is all this
does.

Failure here is contained: extract() returns None rather than raising, so a
format change hides the occupancy chip instead of breaking the dining response.
"""

import json
import logging

from app import http, settings
from app.models import occupancy as occupancy_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "maps_occupancy"
DETAILS_URL = "https://maps.rit.edu/details/{mdo_id}.data"

_MAX_DEPTH = 6


def _resolve(arr: list, index, depth: int = 0):
    """Resolve one turbo-stream index into a plain Python value."""
    if depth > _MAX_DEPTH or not isinstance(index, int):
        return None
    # Negative indices are turbo-stream sentinels (undefined, null, NaN).
    if index < 0 or index >= len(arr):
        return None

    value = arr[index]

    if isinstance(value, dict):
        out = {}
        for raw_key, raw_value in value.items():
            if not raw_key.startswith("_"):
                continue
            key_index = raw_key[1:]
            if not key_index.lstrip("-").isdigit():
                continue
            key = _resolve(arr, int(key_index), depth + 1)
            if isinstance(key, str):
                out[key] = _resolve(arr, raw_value, depth + 1)
        return out

    if isinstance(value, list):
        return [_resolve(arr, item, depth + 1) for item in value]

    return value


def extract(raw: str) -> dict | None:
    """Pull densityData out of a turbo-stream payload. None if not present."""
    first_line = raw.split("\n", 1)[0].strip()
    if not first_line:
        return None

    try:
        arr = json.loads(first_line)
    except json.JSONDecodeError:
        return None
    if not isinstance(arr, list):
        return None

    try:
        key_index = arr.index("densityData")
    except ValueError:
        return None

    marker = f"_{key_index}"
    for entry in arr:
        if isinstance(entry, dict) and marker in entry:
            resolved = _resolve(arr, entry[marker])
            if isinstance(resolved, dict):
                return resolved
    return None


def parse(raw: str, mdo_id: int) -> dict | None:
    """Normalize to the four things we keep, plus the 24 hour series."""
    density = extract(raw)
    if not density:
        return None

    hourly = [
        {
            "hour": row.get("hour"),
            "today": row.get("today"),
            "one_week_ago": row.get("one_week_ago"),
            "average": row.get("average"),
        }
        for row in (density.get("intra_loc_hours") or [])
        if isinstance(row, dict)
    ]

    return {
        "mdo_id": density.get("mdo_id") or mdo_id,
        "count": density.get("count"),
        "max_occ": density.get("max_occ"),
        "open_status": density.get("open_status"),
        "hourly": hourly,
    }


async def fetch(mdo_id: int) -> str:
    return await http.get_text(DETAILS_URL.format(mdo_id=mdo_id))


async def scrape() -> int:
    """Poll the dining locations that actually publish occupancy.

    Verified 2026-08-28: only 5 of 24 locations expose a densityData block. The
    other 19 have no such key upstream, so they are probed occasionally rather
    than every cycle. That keeps a 5 minute cadence honest instead of sending
    thousands of pointless requests a day.

    One location failing never fails the batch. The scrape only counts as failed
    if a location known to have occupancy stopped parsing, which is the signal
    that the turbo-stream format changed.
    """
    mdo_ids = occupancy_model.due_for_poll(settings.OCCUPANCY_REPROBE_MINUTES)
    if not mdo_ids:
        return 0

    stored = 0
    regressions: list[int] = []

    for mdo_id in mdo_ids:
        previously_had = occupancy_model.get(mdo_id) is not None
        try:
            reading = parse(await fetch(mdo_id), mdo_id)
        except Exception as exc:
            log.warning("occupancy fetch failed for mdo %s: %s", mdo_id, exc)
            continue

        if reading is None:
            # Expected for most locations: they simply have no sensor.
            occupancy_model.record_probe(mdo_id, has_density=False)
            if previously_had:
                regressions.append(mdo_id)
            else:
                log.debug("no occupancy published for mdo %s", mdo_id)
            continue

        occupancy_model.record_probe(mdo_id, has_density=True)
        occupancy_model.upsert(reading)
        stored += 1

    if regressions:
        raise ValueError(
            f"occupancy stopped parsing for mdo_id(s) {regressions} that "
            f"previously reported, the turbo-stream format may have changed"
        )

    return stored


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
