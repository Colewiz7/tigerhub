#!/usr/bin/env python3
"""Extract the rest of the campus from OpenStreetMap into a bundled asset.

fetch-osm-paths.py already bundles the walking network. This adds what the map
was missing around it: water, parks and pitches, building footprints RIT does
not publish, entrances, and street names.

Same reasoning as the paths asset. The data is static, the app must work with
no network on a first launch, and a bundled file keeps the count of live
upstreams where it is. It is a separate file from paths.json so that one can
be refetched without touching the other, and it is never merged into RIT's
data.

Rerun it when the campus changes, which is rarely, and commit the result.

    scripts/fetch-osm-features.py [--input cached-overpass.json] [--save-raw raw.json]

OSM data is ODbL. The attribution that obligation requires ships in the asset
header, on the map legend, on the about screen and in NOTICE. Do not remove
any of them.
"""

import argparse
import importlib.util
import json
import math
import pathlib
import re
import sys
import urllib.request

# Same box and user agent as the paths script, so both assets cover the same
# ground and the Overpass operators see one consistent client.
_spec = importlib.util.spec_from_file_location(
    "fetch_osm_paths", pathlib.Path(__file__).resolve().parent / "fetch-osm-paths.py"
)
_paths = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_paths)

BOX = _paths.BOX
AGENT = _paths.AGENT
ENDPOINT = _paths.ENDPOINT
simplify = _paths.simplify
inside = _paths.inside

# Same 2.2m tolerance as the paths. Footprints are drawn at campus zoom, where
# anything finer is invisible.
EPSILON = _paths.EPSILON
PRECISION = _paths.PRECISION

# Below this a footprint is a shed or a bus stop roof. It would draw as a speck
# and cost bytes.
MIN_BUILDING_M2 = 40.0

# Judson and Tiger Stadium stay unmapped. A name that mentions either is
# dropped, so no label or alias can ever be built from this file.
STRIPPED_NAMES = re.compile(r"judson|tiger stadium", re.IGNORECASE)

PARK_LEISURE = "park|garden|playground|common|nature_reserve|dog_park"
PITCH_LEISURE = "pitch"
GREEN_LANDUSE = "grass|recreation_ground|meadow|village_green"

_BBOX = "({south},{west},{north},{east})".format(
    south=BOX[2], west=BOX[0], north=BOX[3], east=BOX[1]
)

QUERY = """[out:json][timeout:120];
(
  way["natural"="water"]{b};
  relation["natural"="water"]{b};
  way["waterway"~"^(river|stream|canal|ditch|drain)$"]{b};
  way["leisure"~"^({park})$"]{b};
  way["leisure"="{pitch}"]{b};
  way["landuse"~"^({green})$"]{b};
  way["building"]{b};
  node["entrance"]{b};
  way["highway"]["name"]{b};
);
out geom;
""".format(
    b=_BBOX, park=PARK_LEISURE, pitch=PITCH_LEISURE, green=GREEN_LANDUSE
)


def fetch() -> dict:
    request = urllib.request.Request(
        ENDPOINT, data=QUERY.encode(), headers={"User-Agent": AGENT}
    )
    with urllib.request.urlopen(request, timeout=240) as response:
        return json.load(response)


def clean_name(tags):
    name = (tags.get("name") or "").strip()
    if not name or STRIPPED_NAMES.search(name):
        return None
    return name


def round_point(p):
    return [round(p[0], PRECISION), round(p[1], PRECISION)]


def area_m2(ring):
    """Shoelace area of a lon/lat ring in square metres, near enough for a size filter."""
    lat0 = sum(p[1] for p in ring) / len(ring)
    kx = 111320.0 * math.cos(math.radians(lat0))
    ky = 110540.0
    total = 0.0
    for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]):
        total += (x0 * kx) * (y1 * ky) - (x1 * kx) * (y0 * ky)
    return abs(total) / 2.0


def geometry(element):
    return [(p["lon"], p["lat"]) for p in element.get("geometry") or [] if p]


def ring_of(points):
    """A simplified closed ring without the repeated closing point, or None."""
    if len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    if len(points) < 3:
        return None
    closed = simplify(points + [points[0]], EPSILON)[:-1]
    if len(closed) < 3:
        return None
    if not all(inside(*p) for p in closed):
        # A footprint cut by the box edge is no footprint. Drop it whole.
        return None
    return [round_point(p) for p in closed]


def line_of(points):
    points = [p for p in points if inside(*p)]
    if len(points) < 2:
        return None
    return [round_point(p) for p in simplify(points, EPSILON)]


def relation_rings(element):
    """The outer rings of a water relation. Each way member is its own ring."""
    rings = []
    for member in element.get("members") or []:
        if member.get("type") != "way" or member.get("role") not in ("outer", ""):
            continue
        points = [(p["lon"], p["lat"]) for p in member.get("geometry") or [] if p]
        # Only members that close on themselves can be filled alone.
        if len(points) > 3 and points[0] == points[-1]:
            ring = ring_of(points)
            if ring:
                rings.append(ring)
    return rings


def extract(payload: dict) -> dict:
    layers = {
        "water": [],
        "waterway": [],
        "park": [],
        "pitch": [],
        "building": [],
        "entrance": [],
    }
    streets = {}
    seen = set()

    elements = sorted(
        payload.get("elements", []), key=lambda e: (e.get("type", ""), e.get("id", 0))
    )
    for element in elements:
        key = (element.get("type"), element.get("id"))
        if key in seen:
            continue
        seen.add(key)
        tags = element.get("tags") or {}
        kind = element.get("type")

        if kind == "node":
            if "entrance" in tags and inside(element["lon"], element["lat"]):
                entry = [round(element["lon"], 6), round(element["lat"], 6)]
                name = clean_name(tags)
                if name:
                    entry.append(name)
                layers["entrance"].append(entry)
            continue

        if tags.get("natural") == "water":
            if kind == "relation":
                layers["water"].extend(relation_rings(element))
            else:
                ring = ring_of(geometry(element))
                if ring:
                    layers["water"].append(ring)
        elif "waterway" in tags and kind == "way":
            line = line_of(geometry(element))
            if line:
                layers["waterway"].append(line)
        elif "building" in tags and kind == "way":
            points = geometry(element)
            if len(points) < 4 or points[0] != points[-1]:
                continue
            if area_m2(points[:-1]) < MIN_BUILDING_M2:
                continue
            ring = ring_of(points)
            if ring:
                layers["building"].append(ring)
        elif tags.get("leisure") == PITCH_LEISURE and kind == "way":
            ring = ring_of(geometry(element))
            if ring:
                layers["pitch"].append(ring)
        elif kind == "way" and (
            re.fullmatch(PARK_LEISURE, tags.get("leisure", "-"))
            or re.fullmatch(GREEN_LANDUSE, tags.get("landuse", "-"))
        ):
            ring = ring_of(geometry(element))
            if ring:
                layers["park"].append(ring)
        elif "highway" in tags and kind == "way":
            name = clean_name(tags)
            line = line_of(geometry(element))
            if name and line:
                streets.setdefault(name, []).append(line)

    layers["street"] = [
        {"name": name, "lines": streets[name]} for name in sorted(streets)
    ]
    return layers


def build_asset(payload: dict) -> dict:
    asset = {
        "attribution": "Map data © OpenStreetMap contributors, ODbL",
        "source": "https://www.openstreetmap.org/copyright",
        "last_verified": "2026-10-29",
        "bbox": {"west": BOX[0], "east": BOX[1], "south": BOX[2], "north": BOX[3]},
        "simplified_metres": 2.2,
    }
    asset.update(extract(payload))
    return asset


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="a cached Overpass response, to avoid refetching")
    parser.add_argument("--save-raw", help="write the raw Overpass response here")
    parser.add_argument(
        "--out", default="client/assets/map/osm_features.json", help="where to write the asset"
    )
    args = parser.parse_args()

    payload = json.load(open(args.input)) if args.input else fetch()
    if args.save_raw:
        pathlib.Path(args.save_raw).write_text(json.dumps(payload))

    asset = build_asset(payload)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(asset, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    counts = ", ".join(
        f"{len(asset[k])} {k}"
        for k in ("water", "waterway", "park", "pitch", "building", "entrance", "street")
    )
    print(f"{counts}, {out.stat().st_size / 1024:.0f} KB -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
