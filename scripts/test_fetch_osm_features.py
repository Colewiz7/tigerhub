"""Self-test for fetch-osm-features.py. Run by ci-checks.py."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fetch_osm_features", HERE / "fetch-osm-features.py")
features = importlib.util.module_from_spec(spec)
spec.loader.exec_module(features)

ASSET = HERE.parent / "client/assets/map/osm_features.json"

# Roughly the middle of the box, so every shape below is inside it.
LON, LAT = -77.67, 43.085
STEP = 0.0003  # about 25 m


def square(size, lon=LON, lat=LAT):
    s = size * STEP
    ring = [(lon, lat), (lon + s, lat), (lon + s, lat + s), (lon, lat + s), (lon, lat)]
    return [{"lon": x, "lat": y} for x, y in ring]


def way(id, tags, geometry):
    return {"type": "way", "id": id, "tags": tags, "geometry": geometry}


def payload(*elements):
    return {"elements": list(elements)}


class ExtractTests(unittest.TestCase):
    def test_same_input_gives_identical_bytes(self):
        raw = payload(
            way(1, {"building": "yes"}, square(2)),
            way(2, {"natural": "water"}, square(4, lon=LON + 0.01)),
        )
        a = json.dumps(features.build_asset(raw), separators=(",", ":"))
        b = json.dumps(features.build_asset(dict(reversed(list(raw.items())))), separators=(",", ":"))
        self.assertEqual(a, b)

    def test_attribution_is_in_the_header(self):
        asset = features.build_asset(payload())
        self.assertIn("OpenStreetMap contributors", asset["attribution"])
        self.assertEqual(asset["source"], "https://www.openstreetmap.org/copyright")

    def test_tiny_buildings_are_dropped(self):
        shed = way(1, {"building": "shed"}, square(0.1))
        hall = way(2, {"building": "yes"}, square(2))
        self.assertEqual(len(features.extract(payload(shed, hall))["building"]), 1)

    def test_building_parts_are_not_footprints(self):
        part = way(1, {"building:part": "yes"}, square(2))
        self.assertEqual(features.extract(payload(part))["building"], [])

    def test_duplicate_elements_count_once(self):
        hall = way(2, {"building": "yes"}, square(2))
        self.assertEqual(len(features.extract(payload(hall, dict(hall)))["building"]), 1)

    def test_rings_are_open_and_footprints_cut_by_the_box_are_dropped(self):
        inside = features.extract(payload(way(1, {"building": "yes"}, square(2))))
        ring = inside["building"][0]
        self.assertNotEqual(ring[0], ring[-1])
        edge = way(2, {"building": "yes"}, square(2, lon=features.BOX[1] - 0.0001))
        self.assertEqual(features.extract(payload(edge))["building"], [])

    def test_layers_are_sorted_by_kind(self):
        layers = features.extract(
            payload(
                way(1, {"natural": "water"}, square(4)),
                way(2, {"leisure": "park"}, square(4, lon=LON + 0.01)),
                way(3, {"leisure": "pitch", "sport": "soccer"}, square(4, lon=LON - 0.01)),
                way(4, {"waterway": "stream"}, square(4)[:3]),
            )
        )
        self.assertEqual(
            [len(layers[k]) for k in ("water", "park", "pitch", "waterway")], [1, 1, 1, 1]
        )

    def test_streets_group_by_name(self):
        line = [{"lon": LON, "lat": LAT}, {"lon": LON + 0.002, "lat": LAT}]
        layers = features.extract(
            payload(
                way(1, {"highway": "service", "name": "Lomb Memorial Drive"}, line),
                way(2, {"highway": "service", "name": "Lomb Memorial Drive"}, line),
                way(3, {"highway": "service"}, line),
            )
        )
        self.assertEqual([s["name"] for s in layers["street"]], ["Lomb Memorial Drive"])
        self.assertEqual(len(layers["street"][0]["lines"]), 2)

    def test_judson_and_tiger_stadium_names_are_stripped(self):
        line = [{"lon": LON, "lat": LAT}, {"lon": LON + 0.002, "lat": LAT}]
        node = {
            "type": "node", "id": 9, "lon": LON, "lat": LAT,
            "tags": {"entrance": "main", "name": "Judson Stadium north gate"},
        }
        layers = features.extract(
            payload(
                way(1, {"highway": "footway", "name": "Tiger Stadium Walk"}, line),
                node,
            )
        )
        self.assertEqual(layers["street"], [])
        self.assertEqual(layers["entrance"], [[round(LON, 6), round(LAT, 6)]])

    def test_a_pitch_keeps_no_name(self):
        pitch = way(1, {"leisure": "pitch", "name": "Judson Field"}, square(4))
        layers = features.extract(payload(pitch))
        self.assertEqual(len(layers["pitch"]), 1)
        self.assertNotIn("Judson", json.dumps(layers))


class BundledAssetTests(unittest.TestCase):
    def setUp(self):
        self.asset = json.loads(ASSET.read_text(encoding="utf-8"))

    def test_attribution_header_is_present(self):
        self.assertIn("OpenStreetMap contributors", self.asset["attribution"])

    def test_stays_under_the_size_budget(self):
        self.assertLess(ASSET.stat().st_size, 200 * 1024)

    def test_no_judson_or_tiger_stadium_string(self):
        text = ASSET.read_text(encoding="utf-8").lower()
        self.assertNotIn("judson", text)
        self.assertNotIn("tiger stadium", text)

    def test_every_layer_is_present_and_filled(self):
        for key in ("water", "waterway", "park", "pitch", "building", "entrance", "street"):
            self.assertTrue(self.asset[key], key)

    def test_no_footprint_is_a_speck(self):
        for ring in self.asset["building"]:
            self.assertGreaterEqual(features.area_m2(ring), features.MIN_BUILDING_M2 * 0.8)


if __name__ == "__main__":
    unittest.main()
