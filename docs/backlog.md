# Backlog

Historical implementation briefs. Everything currently recorded below has been
built; completed briefs remain here because they document constraints and the
reasoning behind the implementation. New unfinished work belongs at the top.

---

## Event dedupe, now that the overlap is measurable  *(done)*

Observed 2026-08-30. CLAUDE.md section 8 decision 2 deliberately shipped **no
dedupe for MVP**, on the grounds that the real overlap should be observed before
anyone writes fuzzy matching. Here it is.

**138 collisions across 1604 events**, and they are *exact* matches on a
normalised title plus the exact start instant. Mostly CampusGroups against
Drupal, both publishing the same official event:

```
co op connections    16 Sep 15:00    campusgroups + drupal
co op connections    23 Sep 15:00    campusgroups + drupal
...
```

**No fuzzy matching is needed.** Lowercase the title, collapse non-alphanumerics
to single spaces, pair that with the UTC instant, and the duplicates fall out
exactly. That is a much smaller job than decision 2 anticipated.

**This only became measurable after the Drupal time fix.** While every Drupal
event was pinned to midnight it could never share an instant with the
CampusGroups copy of itself, so the overlap was invisible and would have looked
like zero.

**When building it, decide which copy wins rather than picking arbitrarily.**
They are not equivalent:

- CampusGroups carries the real organizer (`X-CG-CATEGORY=club_acronym`), which
  is what the grouping, collapsing and muting UI runs on. Drupal hardcodes
  organizer to "RIT".
- Drupal carries `building` and `room` as separate fields. CampusGroups carries
  a single free text `location`.
- Athletics fixtures also appear in Drupal, and the athletics copy has the
  better organizer (the sport) and the fuller location.

So the merge probably wants fields from both rather than one record discarded.
Keep `source` on whatever survives; it is a first class column for a reason.

---

## From Cole's review, 2026-08-30

Everything below came from actually using the app. Marked done where it has
been, so what is left is real.

### Fixed already

- **Glitching when switching pages, and after Customize.** Fourteen stream
  subscriptions were never cancelled, so stale ones kept delivering and an old
  page's result could overwrite the current one.
- **All four tabs laid out constantly**, including the map canvas nobody was
  looking at. Inactive tabs are Offstage now.
- **The caption under the hero number was unreadable.** 85% opacity on a 10px
  semibold sitting on saturated orange.
- **The Today grid spread horizontally with dead space below.** It considers
  height and packing now, so four cards in a tall window go two by two rather
  than three and a widow.
- **Map tab.** The map existed but was buried as a section inside Campus.

### Codex visual handoff completed

**Wordmark stripes.** Redrawn as horizontal wavy markings in the source and
flattened production SVGs.

**Post office hours.** Light and dark mockups plus the service-module rules are
in `docs/post-office-hours-spec.md`.

**Customize dashboard.** Light and dark mockups plus the instance, scope, size
and packing model are in `docs/modular-dashboard-spec.md`.

### Behaviour follow-ups completed

**Post office hours for today.** The data already carries per service, per day
rules; what is missing is a "today" projection so the answer is one line rather
than a table to read. *(done)*

**Split the events widget.** One widget for a single club's events, another for
events in general. The organizer facets and muting already exist, so this is
mostly a matter of a card that is scoped to one organizer. *(done)*

**A calendar view.** For events at least, possibly for dining hours. Worth
deciding which, since a calendar of everything is a different feature from a
month view of one club. Implemented as a seven-day event calendar, optionally
scoped to one organizer. *(done)*

## Motion and loading animations  *(done)*

Requested 2026-08-30. Handed to Codex alongside the map work, so this is
written as a briefing.

Reference the **Caelestia** and **end-4 (illogical-impulse)** dotfiles for feel.
Both are Quickshell/QML, so nothing ports as code, only as idiom: Material 3
expressive easing, gentle spring overshoot, staggered reveals, surfaces that
morph rather than cut. The app already follows their colour spirit (CLAUDE.md
4), and this is the same borrowing applied to motion.

### Read this before writing a single loading spinner

**Most loading animations would be wrong in this app.** CLAUDE.md 3.1 is a hard
requirement: last known data paints instantly on launch, and a stale cache never
shows a spinner or an error. There is exactly one state where a loading
animation is correct, and it is named in the code:

```
DataState.priming   never had data, first run only   <- the ONLY loading state
DataState.ok        fresh
DataState.stale     have data, it is old             <- paint at full opacity
DataState.failing   have data, refresh errored       <- paint at full opacity
```

Putting a spinner on `stale` or `failing` would undo the entire offline first
design. Those two states get a quiet timestamp, never a loader.

**And priming is brief.** Measured on a wiped cache, 2026-08-30:

```
dining, makerspace, recreation   1.0 s
campusgroups (1 MB iCal)         2.0 s
drupal (10 paginated requests)   2.6 s
athletics                        4.6 s
```

So a loading animation has about a second to be useful on the card people look
at first. Anything with a long intro will still be playing after the data
arrives, which makes the app feel slower than it is. Prefer a skeleton that
settles into content over a spinner that has to finish.

### Where motion actually earns its keep here

Named specifically, because "add animations" applied evenly would be worse than
nothing:

- **Data updating in place.** The refresh ticker replaces content behind the
  user every two minutes. Right now values swap instantly, which reads as a
  glitch. A short cross fade, or a number that counts to its new value, turns it
  into an update. This is the highest value item on the list.
- **The scalloped badge hero number.** One per card, the biggest thing on it.
  Worth a settle on first appearance and on change.
- **`ArcProgress`** (`widgets/`), the occupancy indicator: sweep to value rather
  than appearing at it.
- **The detail sheet.** Tapping a dining row opens it. A Hero from the row's
  badge into the sheet is the obvious win.
- **Tab and section switches.** Four tabs, plus the section rails in Campus and
  Settings. Currently hard cuts.
- **The jump rail's active marker** (`widgets/jump_list.dart`) tracks scroll
  position. It should slide between entries, not blink.
- **Staggered reveal of a list on first paint only.** Never on a refresh, or
  every tick makes the whole list dance.

### Where motion must not go

- Anything that delays content already in hand. Cache paints now.
- `stale` and `failing`. See above.
- The status colours. CLAUDE.md 4: status always ships with a text label, never
  colour alone. Motion does not count as a label either, and a pulsing "open"
  chip is not an accessible substitute for the word.
- Long or looping ambient motion on a screen someone glances at for four
  seconds.

### Constraints

- **Respect reduced motion.** `MediaQuery.disableAnimationsOf(context)` and
  `accessibleNavigation`. Every animation needs a still fallback that is not
  simply "nothing renders". This is usually forgotten and is not optional.
- **Ask before adding a dependency** (CLAUDE.md). Flutter's built in implicit
  animations, `AnimatedSwitcher`, `Hero`, `TweenAnimationBuilder` and
  `AnimationController` cover everything above. `flutter_animate` is a
  dependency and needs Cole's approval first.
- Curves already in use: `Curves.easeOutCubic` at 260 ms in
  `jump_list.dart`. Match that unless there is a reason not to.
- Targets are Linux desktop and Android. Assume a compositor that may already
  be doing its own animation; do not fight it.

---

## Campus map, with events placed on it  *(done)*

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

## Masthead wordmark: orange on "Tiger", with tiger striping  *(done)*

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

## Mailing address: copy buttons, and a default address that drives the app  *(done)*

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
