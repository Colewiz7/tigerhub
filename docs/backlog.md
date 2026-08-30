# Backlog

Things decided but not yet built. Newest first. Anything here is a real
request, not a maybe. If something turns out to be a bad idea, delete it and
say why rather than leaving it to rot.

---

## Campus map, with events placed on it

Requested 2026-08-30. Likely handed to Codex/ChatGPT, so this is written as a
briefing rather than a note to self.

**The good news: the data is already being downloaded and then thrown away.**

`maps.rit.edu/categories/<id>.data` returns Remix turbo-stream, and the app
already fetches six of those categories and already has a full decoder at
`client/lib/data/turbo_stream.dart`. What comes out is **plain GeoJSON**:

```json
{
  "type": "Feature",
  "geometry": {"type": "Point", "coordinates": [-77.676933, 43.082862]},
  "properties": {
    "id": 8117, "mdo_id": 3016, "name": "Hydration Station - LOW 1st floor 2",
    "abbreviation": "LOW", "buildingNumber": "012", "floorLevel": "1st floor",
    "roomNumber": "1110", "descShort": "Corner of hallway, next to bathrooms",
    "geometry_id": 7424, "images": []
  }
}
```

`parseCampusPlaces` in `client/lib/data/sources/campus_places.dart` reads only
`properties` and drops `geometry`. Keeping it is a small change, and it is the
whole foundation for this feature.

**Facts worth not rediscovering:**

- Coordinates are WGS84 in **GeoJSON order, longitude first**. Easy to plot
  transposed and end up in the Indian Ocean.
- Both `Point` and `Polygon` geometries are present, so **building outlines are
  in there**, not just pins. That is what makes a real campus map possible
  rather than dots on a blank field.
- `mdo_id` is the join key to dining locations and to the occupancy readings, so
  a dining pin can carry live occupancy with no extra request.
- The payload also carries `currentEvent`, `eventData`, `eventMenus` and
  `event_id`. **RIT's own map already places events**, so look at what is in
  those before building an event placement scheme from scratch.
- Every response embeds the whole category menu, so one request can enumerate
  every category (CLAUDE.md 7.9.2). Known ids: 35 Sustainability, 259 Retail,
  236 Study Area, 279 Lactation Rooms, 11 Parking. The six parents currently
  fetched are 35, 19, 27, 23, 15, 7.

**The hard part is placing events, and it is a joining problem, not a map
problem.** Events carry no coordinates:

- Drupal events have `building` as a full name ("Frank E. Gannett Hall") and
  `room`.
- CampusGroups events have free text `location` ("CPC-2610 Bamboo Room"), and
  many have none at all.

So it needs a building lookup. The map payload gives `abbreviation` + `name` +
`buildingNumber` + coordinates for every place, which is enough to build one,
but the matching from prose to building is the real work. Expect fuzzy matching
and expect it to be wrong sometimes: **an event pinned to the wrong building is
worse than an event with no pin**, so leave unmatched events off the map rather
than guessing, and say how many were left off.

**Rendering: this is a real decision, do not just reach for Mapbox.**

- A tile map (Mapbox, Google, OSM via `flutter_map`) needs a new dependency, and
  Mapbox and Google need an API key. **Ask Cole before adding either**
  (CLAUDE.md rule). A key also means the app stops working offline, which is a
  hard requirement in CLAUDE.md 3.1.
- **Painting the GeoJSON directly on a `CustomPainter` needs no dependency, no
  key, and no network.** The building polygons are already in hand, the campus
  is small enough to fit one viewport, and it can be drawn in the app's own
  scheme colours. That is almost certainly the right answer here: it is the only
  option that fits both the offline requirement and Cole's ask that it match the
  theme.

A generic tile map will look like a generic tile map, and will fight the warm
palette in CLAUDE.md section 4 no matter what is drawn on top of it.

---

## Masthead wordmark: orange on "Tiger", with tiger striping

Requested 2026-08-30.

Currently `_Wordmark` in `client/lib/app_shell.dart` splits the name at the
internal capital and puts `scheme.onSurface` on "Tiger" and `scheme.primary`
on "Hub". **Swap it.** "Tiger" carries the orange, "Hub" is the quiet half.

Then stripe the "Tiger" half like a tiger: dark stripes over the orange, in a
soft near-black rather than pure black, tuned to sit against that orange
without going harsh.

**How to actually do the stripes.** A `TextSpan` cannot carry a pattern, so
this needs one of:

- a `ShaderMask` over just the "Tiger" span with a repeating `LinearGradient`
  of hard stops (orange, dark, orange), angled maybe 12 to 20 degrees off
  vertical. Cheapest, and the stripes stay straight rather than following the
  letterforms;
- or a `CustomPainter` that paints the glyphs and clips the stripe shapes to
  them, which allows tapered stripes that actually look drawn.

Start with the ShaderMask. If the straight stripes read as a barcode rather
than as an animal, escalate to the painter.

**Watch the contrast.** The stripes cut the effective lightness of the orange,
so check the wordmark against both light and dark surfaces before shipping.
CLAUDE.md section 4 says colour is validated, never eyeballed, and a striped
wordmark is exactly the kind of thing that looks fine on the dark theme and
turns to mud on the light one.

Related: [[app-icon]] uses the same tiger idea, so the two should agree.

---

## Mailing address: copy buttons, and a default address that drives the app

Requested 2026-08-30.

**The problem.** Web order forms split an address across several fields, so
having the address as one block means selecting a piece at a time by hand every
single time. That is the annoying part, and it is what the copy buttons are for.

**What it should do:**

- Show the address as its own lines, each line with **its own copy button**, so
  a form asking for street, city, state and ZIP separately can be filled by
  tapping down the list.
- Also a **copy the whole address** button, for the forms that take one blob.
- A button that **changes which address you are looking at**, for when you need
  someone else's area or you are checking a different hall.

**The bigger half: a default address set during first run setup.**

- First launch asks where you live, once, and that becomes the default.
- The address screen then opens on your address instead of asking every time.
- That default is not only for mail. It is a **location anchor**, and other
  parts of the app should use it: ordering dining locations by proximity, and
  anything else where "nearest to me" beats alphabetical.

**Note for whoever builds it.** The proximity half needs coordinates per housing
area, which the current `housing_areas.json` does not carry, and the zone based
mail model (CLAUDE.md 7.9) means an "address" is an office plus a line 2 format,
not a street address per hall. So the anchor is probably the residence area's
own location, not the post office's. Check that before designing the sort.
