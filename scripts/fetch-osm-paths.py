#!/usr/bin/env python3
"""Extract the campus walking network from OpenStreetMap into a bundled asset.

maps.rit.edu publishes no line geometry at all. Every one of its categories is
Point or Polygon, so buildings and pins were the only things the map could
draw, and nothing showed how you actually get between them.

OSM has the footpaths. This pulls them once and writes a small asset rather
than adding a runtime upstream, because:

  - the walking network is static, so refetching per install buys nothing
  - the app must work offline on a first launch (docs/notes.md 3.1), and a bundled
    asset is the only thing that satisfies that on day one
  - it keeps the count of live upstreams where it is

Rerun it when the campus changes, which is rarely, and commit the result.

    scripts/fetch-osm-paths.py [--input cached-overpass.json]

OSM data is ODbL. The attribution that obligation requires ships in the asset
header and on the app's about screen. Do not remove either.
"""

import argparse
import json
import math
import pathlib
import sys
import urllib.request

# Wider than the fitted campus view, so a path does not stop at the edge of
# the screen, but tight enough to leave the rest of Henrietta out.
BOX = (-77.695, -77.657, 43.073, 43.096)

# Roughly 2.2m. Below what anyone can see at campus zoom, and it removes 43%
# of the nodes: 9550 to 5453, which is 216 KB down to 114 KB.
EPSILON = 0.00002

# 5 decimal places is about 1.1m, matching the simplification above. More
# digits would store noise.
PRECISION = 5

FOOT = {"footway", "path", "steps", "pedestrian", "cycleway"}
ROAD = {
    "service", "unclassified", "residential", "tertiary",
    "primary", "secondary", "track", "living_street",
}

QUERY = """[out:json][timeout:90];
(
  way["highway"~"^({kinds})$"]({south},{west},{north},{east});
);
out geom;
""".format(
    kinds="|".join(sorted(FOOT | ROAD)),
    south=BOX[2], west=BOX[0], north=BOX[3], east=BOX[1],
)

ENDPOINT = "https://overpass-api.de/api/interpreter"
AGENT = "TigerHub/0.1 (personal RIT campus app; https://github.com/Colewiz7/tigerhub)"


def fetch() -> dict:
    request = urllib.request.Request(
        ENDPOINT,
        data=QUERY.encode(),
        headers={"User-Agent": AGENT},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.load(response)


def simplify(points, epsilon):
    """Ramer-Douglas-Peucker, iterative so a long way cannot blow the stack."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        start, end = stack.pop()
        x0, y0 = points[start]
        x1, y1 = points[end]
        dx, dy = x1 - x0, y1 - y0
        span = math.hypot(dx, dy)
        worst, index = 0.0, start
        for i in range(start + 1, end):
            x, y = points[i]
            if span:
                distance = abs(dy * x - dx * y + x1 * y0 - y1 * x0) / span
            else:
                distance = math.hypot(x - x0, y - y0)
            if distance > worst:
                worst, index = distance, i
        if worst > epsilon:
            keep[index] = True
            stack.append((start, index))
            stack.append((index, end))
    return [p for p, k in zip(points, keep) if k]


def inside(lon, lat):
    return BOX[0] <= lon <= BOX[1] and BOX[2] <= lat <= BOX[3]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="a cached Overpass response, to avoid refetching")
    parser.add_argument(
        "--out",
        default="client/assets/map/paths.json",
        help="where to write the asset",
    )
    args = parser.parse_args()

    payload = json.load(open(args.input)) if args.input else fetch()

    ways = {"foot": [], "road": []}
    for way in payload.get("elements", []):
        highway = way.get("tags", {}).get("highway")
        if highway not in FOOT and highway not in ROAD:
            continue
        points = [(p["lon"], p["lat"]) for p in way.get("geometry") or []]
        # Clip rather than reject, so a path leaving the box keeps the part
        # that is on campus.
        points = [p for p in points if inside(*p)]
        if len(points) < 2:
            continue
        points = simplify(points, EPSILON)
        ways["foot" if highway in FOOT else "road"].append(
            [[round(x, PRECISION), round(y, PRECISION)] for x, y in points]
        )

    asset = {
        "attribution": "Map data © OpenStreetMap contributors, ODbL",
        "source": "https://www.openstreetmap.org/copyright",
        "last_verified": "2026-08-30",
        "bbox": {"west": BOX[0], "east": BOX[1], "south": BOX[2], "north": BOX[3]},
        "simplified_metres": 2.2,
        "foot": ways["foot"],
        "road": ways["road"],
    }

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(asset, separators=(",", ":")))
    nodes = sum(len(w) for kind in ("foot", "road") for w in ways[kind])
    print(
        f"{len(ways['foot'])} footpaths, {len(ways['road'])} roads, "
        f"{nodes} nodes, {out.stat().st_size / 1024:.0f} KB -> {out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
