# TigerHub notes

The long form notes behind the app: the endpoints, what each one actually
returns, and why the decisions went the way they did. The README is the short
version.

**Not affiliated with, endorsed by, or officially connected to Rochester
Institute of Technology.** Student built and student maintained. That disclaimer
ships in the README, the repo, and the app's about screen.

---

## 1. Conventions

- No em dashes, anywhere. Commas, periods or parentheses instead.
- Small commits, clear messages.
- Think before adding a dependency. Most of what has been reached for here
  turned out to be a hundred lines (see `ical.dart`, `campus_time.dart`).
- Art lives in `assets/generated/`, spec in `assets/generated/SPEC.md`. Do not
  inline draw SVG in widget code.

## 2. Development environment

- Linux only, on Hyprland. There is no Mac here and never will be, which is
  why the iOS story in section 3 ends where it does.
- Everything below about screenshots is Hyprland specific and can be ignored
  on another desktop.

### 2.1 Screenshotting the client

**Captures require the TigerHub window to be focused, and are refused
otherwise.** `scripts/dev shot` and `shot-tabs` both check
`hyprctl activewindow` and stop if it is anything else.

**Cropping to the window is not enough, and the reason matters.** `grim -g`
records the screen at a set of coordinates, not a window's own buffer, so
anything drawn on top of the app is what lands in the file. Cropping only rules
out grabbing the wrong *region*.

This has now leaked three times: a browser, a lock screen, and a notification
panel full of messages. The third got through the window-crop fix, because
compositor overlays (Caelestia's drawers, bars) are **layer-shell surfaces**.
They never appear in `hyprctl clients`, and the ones on this machine are full
screen and permanently mapped with alpha 1, so their geometry says nothing about
whether they are currently drawn. There is no way to detect them from the window
list.

Two guards were tried and rejected before settling on focus:

- *Refuse when a layer surface overlaps.* Every capture would be refused, since
  `caelestia-drawers` is always full screen.
- *Check that the image's corners match each other.* Rejected a legitimate
  capture on its first run, because at narrow widths a card reaches the corner.
  A heuristic that deletes good captures is worse than no heuristic.

Requiring focus works because a drawer, a lock screen or another app all take
focus away. **The cost is that captures are no longer automatic: you have to
click the window first.** That is the right trade for something that has leaked
personal content three times.

`shot-tabs` needs focus for a second reason anyway: it drives tabs with `wtype`,
which types into whatever holds focus. Unfocused, it types "1234" into someone's
terminal.

```bash
scripts/dev shot [outfile]     # does all of the below
```

`scripts/dev` no longer starts anything. There is no backend, so `up`, `down`,
`restart`, `logs`, `setup` and `api` are gone. `status` and the new `data`
report what the app has scraped onto disk, and `reset` wipes it.

Manually:

```bash
GEO=$(hyprctl clients -j | python3 scripts/_geometry.py)
grim -g "$GEO" /tmp/shot.png
```

- **The window class is `dev.colewiz.tigerhub`, not `tigerhub`.** Waiting on the wrong
  string hangs forever. It comes from `--org dev.colewiz` at project creation.
- Wait for the window by class, then give it about 6 seconds to paint before capturing.

**`hyprctl dispatch` is broken on this machine.** Hyprland 0.56.2 routes dispatch through
a Lua interpreter, and the documented argument forms all fail to parse:

```
$ hyprctl dispatch workspace 2
error: [string "return hl.dispatch(workspace 2)"]:1: ')' expected near '2'
```

Bracket rules (`[workspace 3 silent] cmd`), `--batch`, quoted Lua strings, and the
`hl.dsp.*` namespace were all tried and all fail. So **do not build a screenshot flow on
workspace switching**, and never write `hyprctl dispatch ... 2>/dev/null`, which is how
this went unnoticed for several rounds. Cropping to the window geometry sidesteps the
problem entirely and is privacy-safe regardless of which workspace the app lands on.

Workspaces are bound to `super + <number>` for moving it by hand.

## 3. Architecture (settled)

- **Client only. There is no server.** A single Flutter codebase targeting
  **Linux desktop and Android**, which scrapes RIT directly on the device,
  normalizes the data, and caches it to disk.
- **Why the server went away (2026-08-30).** It ran on a homelab that gets
  rebuilt and rebooted for other projects, so its uptime could not be relied on
  for something you check between classes. Trading a dependency you cannot
  promise for one you control was the right call even at the cost below.
- **What it cost: the Web target, and with it iOS.** Four of six upstreams send
  no `Access-Control-Allow-Origin`, so a browser cannot reach them. Measured,
  not assumed:

  ```
  tigercenter.rit.edu           no ACAO
  www.rit.edu                   no ACAO
  maps.rit.edu                  no ACAO
  ritathletics.com              no ACAO
  make.rit.edu                  ACAO: https://make.rit.edu   (its own origin only)
  locations.fdmealplanner.com   ACAO: *
  ```

  Native platforms have no such restriction, so Linux and Android are
  unaffected. Web was the iOS story, since native iOS is impossible without a
  Mac, so **there is currently no iOS path.** Accepted deliberately.

- **The alternative that was considered and rejected.** GitHub Actions could run
  the scrapers on a schedule and publish about 62 KB of JSON to a public branch,
  which both keeps Web alive (GitHub's static hosts send `ACAO: *`) and removes
  the homelab. It was rejected because it requires the data to be public, and
  this stays private. Revisit only if the repo ever goes public.

### What moved onto the device, and what that obliges

The scrapers, the hours recurrence resolver, and both turbo-stream decoders are
now in `client/lib/data/`. Two obligations came with them and **matter more**
here, not less, because there is now one scraper per install rather than one in
total:

1. **Cadence.** `local_backend.dart` refreshes a source only when its snapshot is
   older than that source's interval. Opening a tab five times does not scrape
   five times. Section 6 still applies in full.
2. **Identification.** `upstream.dart` is the only place the User-Agent is set,
   and every outbound call goes through it.

**FD menus changed shape.** The server rotated one location per run through all
twelve. That is wrong on a device: it would pull 7 MB for a location the user
never opens. Menus are now fetched **on demand for the location being viewed**
and cached for a day, so someone who only checks Gracie's downloads 7 MB rather
than 84 MB.

**Nothing refreshes unless something asks.** There is no APScheduler on a
device. `AppShell` runs a two minute ticker that calls refresh, and each
source's own cadence gates whether that actually scrapes. Asking often is nearly
free because snapshots are held decoded in memory. Without the ticker an app
left open all day shows the data it had at launch, which is not what "live
occupancy" means.

**Occupancy keeps a probe record**, the same idea as the server's
`occupancy_probe` table. Only 5 of 24 locations publish occupancy (mdo 123, 125,
129, 163, 604, re-confirmed on device 2026-08-30), so polling all of them every
five minutes would be 6,912 requests a day for 5 useful answers. Known sensors
are polled every run; the other nineteen are rechecked twice a day, capped. The
first run probes everything at once and checkpoints after each location, so
discovery finishes in one pass and resumes if interrupted.

**A snapshot of everything is about 2 MB on disk.** Stored as one JSON file per
source under the app support directory, written temp-then-rename so a crash
leaves the previous good copy rather than a truncated one.

### The port was verified, not assumed

Roughly 1400 lines of scraping and 200 lines of date math were translated from
Python. Every source is pinned against the backend's own output over captured
upstream payloads, and the golden files were produced by the Python itself, so
they keep testing the port now that the backend is gone:

| Source | What is compared |
|---|---|
| Dining hours | all 24 locations at four frozen instants, including inside an overnight span and the day after DST ends |
| CampusGroups | 962 events, every field |
| Athletics | 182 fixtures, every field, mixing UTC timestamps with `VALUE=DATE` all days |
| Drupal | 460 records, every field except the three the port deliberately fixes |
| Campus places | 236 places through the full turbo-stream decoder |
| Occupancy | one 226 KB payload through the targeted extractor |
| Recreation | 9 facilities, 75 rows |

**Two backend bugs were found this way and are fixed in the port:**

1. **Drupal published times were thrown away.** It sends `"3:00 PM"`, and the
   backend only tried 24 hour formats, so every parse failed silently and fell
   through to all-day. 456 of 460 official RIT events lost their real start
   time, which is why the Events tab showed everything from RIT as ALL DAY.
2. **Events sorted by timestamp text.** The feeds store different UTC offsets,
   so `16:00:00-04:00` sorted as earlier than `13:15:00Z` when it is nearly
   seven hours later. The port compares instants.


## 3.1 Offline first (hard requirement, not a nice to have)

**The app must be fully usable with no network at all.** Treat this as a
correctness requirement, the same as any other. Campus wifi drops, RIT's own
endpoints go down, and a phone in a basement has no signal. None of that may
produce a broken app.

This got *more* important when the server went away, not less. There is no
longer a warm cache sitting on a machine somewhere that has already done the
scraping: a device with no network has only what it stored last time.

- **Cache every API response locally**, keyed by endpoint, persisted across launches.
- **Render last known data instantly on launch. No cold start spinner.** Paint from cache
  first, then refresh in the background and update in place.
- **Show a subtle stale indicator with the last updated time** when data is old or the
  refresh failed. A small line of text or a muted chip, not a banner and not a modal.
- **Never show an error screen for a stale cache.** An error screen is only ever correct
  when there is genuinely nothing to show, meaning a first run that has never succeeded.
- Every list endpoint still returns `{data, stale, last_updated}`. That envelope
  was the server's, and it was deliberately kept when the scraping moved onto
  the device, so the presentation layer did not have to be rewritten alongside
  everything else. `local_backend.dart` computes the same staleness signal from
  the snapshot's age against that source's cadence.
- **The bundled config works with no network on a first launch, ever.** Post
  office hours, mailing address formats and SHED hours ship as assets, so the
  thing you look up while standing at a counter with no signal always answers.

## 4. Design language (settled 2026-08-28)

Warm, in the Caelestia/matugen spirit: the whole UI is one coherent scheme
rendered, not a set of colours picked per widget. That scheme is generated from a
single seed the app ships with, **not** from the user's wallpaper. Tokens live in
`client/lib/theme/tokens.dart` and `app_theme.dart`. Reuse them, do not re-derive.

**Colour ships with the app. It does not follow the wallpaper.**

**Reversed 2026-08-30.** Wallpaper following was briefly the default. That was
wrong: this runs on many different desktops and for other people, and
a scheme generated from whatever photo someone set as their background is not a
design, it is a guess. It can also be unreadable, and it broke the status
colours (see below).

- **Default, everywhere:** `ColorScheme.fromSeed` on RIT orange `#F76902`, in
  both light and dark, following the system setting. One seed, so both modes
  stay consistent. M3's own `surfaceContainer*` steps are used directly, since
  they separate cleanly (luminance steps of 4 to 14 in both modes).
- **Following the wallpaper is opt in, off by default, Linux only.** It reads
  the Caelestia scheme file, watches it, and rebuilds live. Kept because it is
  genuinely nice on a machine that has one. Toggle in Settings, Appearance, or
  the palette button in the app bar.
- `--dart-define=FORCE_SEED=true` pins the built-in palette and disables the
  opt in entirely.
- The generated file's own `surfaceContainer*` roles sit within a few points of
  each other, so when following a wallpaper the nesting is re-derived by
  blending `surfaceTint` over `surface`.

### Colour is validated, never eyeballed

Run the `dataviz` skill's `scripts/validate_palette.js` before shipping any
palette or chart colours. It has already caught two real bugs that would not
have been visible by looking:

1. **The shipped status colours were broken.** `Blend.harmonize` rotated red and
   amber so far toward the orange primary that they collapsed: **dE 1.0 apart in
   deuteranopia, dE 4.8 in normal vision.** CLOSED and BUSY were effectively the
   same colour. Replaced with a 10 percent hue nudge plus deliberate lightness
   separation. Now dE 9.4 protan / 18.0 normal in dark, dE 11.6 deutan / 17.0
   normal in light, all pairs, both validated against their own surface.
2. **A two series occupancy chart would have been unreadable.** On a
   wallpaper-derived palette `primary` and `onSurfaceVariant` measured dE 10.9,
   under the 15 floor. The chart became one series plus a sentence instead.

**Standing rules that follow:**
- Red against green is the fundamental colourblindness case and no hue choice
  fixes it. Status colours are separated by **lightness** as well as hue, which
  is why they deliberately sit outside a uniform lightness band.
- The dark "busy" amber is deliberately pale. Deepening it for more chroma drops
  its separation from green to dE 2.0 in protanopia.
- Status colours always ship with a text label, never colour alone.
- Prefer form and words over hue when a comparison must be made.

**Shape**
- The signature is a scalloped "cookie" badge, `Shapes.badge`, one per card at most,
  for the single most important number on that card.
  **Gotcha:** `StarBorder` asserts `pointRounding + valleyRounding <= 1`, so the
  1.0/1.0 pair throws at construction. Ours splits the budget 0.5/0.5.
  With the rounding capped, softness comes from geometry. Values picked by rendering a
  variant grid at 150px: **7 points at innerRadiusRatio 0.93**. 8 at 0.90 shows obvious
  straight segments and reads as an octagon; above ~0.95, or above 8 points, it collapses
  into a plain circle.
- **The hero is card level, not row level.** It must answer the question the card exists
  to answer. Dining shows the count of locations open now, not one location's occupancy,
  because that location was usually not even among the visible rows.
- Cards 30. Inner surfaces 20. Chips, buttons, and the occupancy indicator are full
  pills (`StadiumBorder`). **Nothing in the app is rounded at 8 or below.**
- Dropdowns use the split control pattern: a wide pill for the value, a separate small
  accent pill holding the chevron.

**Indicators**
- Circular: `ArcProgress`, a partial sweep with a gap at the bottom, thick stroke,
  round caps, darker track ring behind. `CircularProgressIndicator` cannot do a partial
  sweep, hence the small custom painter. Written once, reused.
- Linear: `SegmentedBar`, two pieces with a gap, never one continuous bar.

**Type**
- Rubik, bundled as a variable font asset in `client/assets/fonts/`. Not fetched at
  runtime, because the app must work offline. Weights come from `fontVariations` on the
  wght axis, see `Weights` in tokens.
- The key number per card is oversized and light. Everything else recedes.
- Labels under big numbers are small, muted, and wide tracked.
- Icons are the built-in `Icons.*_rounded` set, which covers the Material Symbols
  Rounded look with no extra dependency.

**Tabs**
- Icon stacked above label, accent underline on active, muted when inactive. No pill
  backgrounds and no boxes. Quiet, like an editor tab strip.
- Four areas: Today, Dining, Events, Campus. Today holds the reorderable card grid, and
  the "+N more" footers navigate to the matching tab.

**Layout**
- The grid is responsive: 1 column under 700, then 2, 3, and 4 as width grows. Cards grow
  taller to fill spare vertical room, clamped 344 to 560, and BoundedList turns that
  height into extra rows automatically.
- Drag handles appear on hover, not permanently. The space is always reserved so
  revealing one never shifts the title.
- **Long scrolls get a left jump rail.** Anything that is one long list of groups
  (Dining by category, Events by organizer) uses `widgets/jump_list.dart`, and
  anything that is stacked sections (Campus, Settings) uses
  `widgets/section_nav.dart`. Both drop the rail on a narrow window, where it
  costs more width than it gives.
  **Gotcha:** `ListView.builder` has not built a far-off group, so its
  `GlobalKey` has no context and `Scrollable.ensureVisible` silently does
  nothing. `JumpList._jumpTo` walks the viewport a screen at a time until the
  target exists, then animates the last hop. Do not simplify that loop away.
  Both widgets measure with `LayoutBuilder`, never `MediaQuery.sizeOf`: they sit
  inside a tab under a masthead, so the window width is not the width they get,
  and in tests devicePixelRatio silently divides it.

**Density**
- Glanceable, not a system dashboard. One hero per card, never a wall of gauges.
- Events carries no gauge at all.
- Times read as words where that is clearer: "until midnight", "noon".

## 5. Features (priority order)

1. Dining hours and locations for all campus dining spots
2. Campus events tab and a large live calendar
3. "What's my housing address?" lookup (pick residence hall, get correct mailing format)
4. Post office hours (Global Village and Perry Hall)
5. Dining specials and visiting chefs
6. SHED makerspace hours and real time equipment availability
7. Building open times and Global Market info
8. Modular home screen: drag and drop reorderable cards, tabs per area
9. Offline caching, plus local notifications ("visiting chef today")

### Out of scope

**Dining dollars / Tiger Bucks balance. Do not build.** Requires piggybacking an authenticated Shibboleth + Duo session against `tigerspend.rit.edu`. The only project that did it (`github.com/erwijet/tigerwatch`) is archived and broken because RIT changed the auth flow. **Never store credentials for anything.**

## 6. Scraping ethics (enforce in code, not just docs)

- Cache aggressively. Scheduled scrapes only, **never scrape per request**.
- Cadence: dining hourly, events every few hours, makerspace every 15 minutes.
- Honest, identifiable User-Agent on every outbound request. Include a contact.
- Never hit login gated endpoints. Never store anyone's credentials.
- Every upstream call goes through one HTTP client wrapper that enforces the UA, timeouts, and retry/backoff. No ad hoc `httpx.get` scattered around.

---

## 7. Recon findings (verified 2026-08-28)

Everything below was tested live, not assumed. Sample payloads are in `docs/recon/`.

### 7.1 Summary table

| Source | Endpoint | Auth | Reliability | Effort |
|---|---|---|---|---|
| TigerCenter dining | `GET tigercenter.rit.edu/tigerCenterApi/tc/dining-all?date=YYYY-MM-DD` | **None** | High | **Trivial** |
| CampusGroups events | `GET campusgroups.rit.edu/ical/rit/ical_rit.ics` | None | High | **Trivial** |
| RIT Drupal events | `GET www.rit.edu/jsonapi/node/event` | **None** | High | **Low** |
| Makerspace equipment | `POST make.rit.edu/graphql` | **None** | High | **Low** |
| Makerspace hours | `POST make.rit.edu/graphql` | None | Medium | Low |
| FD MealPlanner menus | `locations.fdmealplanner.com` + `apiservicelocatorstenantrit.fdmealplanner.com` | None | Medium | Medium |
| Maps occupancy | `GET maps.rit.edu/details/<mdoId>.data` | None | Medium | **High** (turbo-stream) |
| Post office / housing | static JSON config in repo | n/a | High | Trivial |

### 7.2 TigerCenter dining (the big win)

The Angular route `/tigerCenterApp/api/hours-and-locations` serves the SPA shell. The real data call was captured with Playwright, and the app's own bundle confirms the base:

```js
Et = { production: true, TC: "/tigerCenterApi/tc/", TCAuth: "/tigerCenterApi/login_shib/tc/" }
A.get("dining-all?date=" + e)
```

**Endpoint:** `https://tigercenter.rit.edu/tigerCenterApi/tc/dining-all?date=2026-08-28`

- **No auth, no cookies, no referer, no custom headers.** Plain `curl` returns 200 and 24 KB of JSON.
- `login_shib/tc/user` returns `{"username":"Public Username","authorities":[{"authority":"USER"}]}` unauthenticated, which is why the public tier works.
- Everything under `TCAuth` (`diningHoursData`, `enrolledClasses`, `shopping-cart`, and so on) **is auth gated. Do not touch it.**
- Sibling public endpoints: `tc/maintenance` (per feature health flags, useful for a graceful degradation banner), `tc/currentTerms`, `tc/url`, `tc/lastUpdated`.
- Per location variant: `tc/dining-single?date=YYYY-MM-DD&locId=23`.

**Response shape** (`{"locations": [...]}`, 24 locations):

```
id, name, summary, description (HTML), mapsUrl, department, mdoId, mapId, mrkId, catId
contacts[]
events[]              # opening hours
  id, name ("Fall 2026"), locationId, locationName
  startTime "10:30:00", endTime "21:00:00"
  startDate "2026-08-16", endDate "2026-12-24"
  daysMask 62, daysOfWeek ["MONDAY",...], infinite false
  menuTypes ["LUNCH"]
  exceptions[]        # per date overrides, same shape plus `open: bool`
menus[]
  id, name, description, price, category, eventId
```

Key points:
- Hours are a **recurrence model**, not a daily list: a term long window plus `daysOfWeek` plus dated `exceptions` that override it. The backend must resolve this into concrete per day open/close spans. This is the one piece of real logic in the dining feature.
- `menus[].category == "Visiting Chef"` means **visiting chefs come free from this endpoint.** Confirmed 4 live entries today across Crossroads, Brick City, and RITZ. No scraping of `rit.edu/dining/menus` required.
- `mdoId` is the join key to `maps.rit.edu`.
- 24 locations including Gracie's, Crossroads, Brick City, RITZ, Global Market, Corner Store, and the RIT Food Truck.

### 7.3 CampusGroups events iCal (easiest win, confirmed)

`https://campusgroups.rit.edu/ical/rit/ical_rit.ics` 302 redirects to a CampusGroups CDN and returns 200, `text/calendar`, about 1 MB.

- Parses cleanly with the Python `icalendar` library. **921 events, 699 of them in the future**, spanning 2026-05-30 to 2027-05-07.
- **Every field is present on 100% of events**: `DTSTART`, `DTEND`, `SUMMARY`, `LOCATION`, `DESCRIPTION`, `URL`, `UID`, `ORGANIZER`, `CONTACT`, `CATEGORIES`, `CREATED`, `LAST_MODIFIED`, `SEQUENCE`.
- **Zero `RRULE`s.** Recurring events come pre expanded, so no recurrence engine needed. Big simplification.
- `ORGANIZER;CN="RIT FoodShare"` gives the club name. 60 distinct clubs.
- `CATEGORIES` carries an `X-CG-CATEGORY` param, either `club_acronym` or `event_type`. Usable event types: Religious/Spiritual (313), Attendance Tracking (232), Meeting (99), Event (85), Training/Workshop (48), Recreation (41), Tabling/Outreach (30), University Wide Event (10), Blood Drive (9).
- Caveat: heavily skewed to a few orgs (FoodShare alone is 213 events). Filtering and grouping by organizer/type matters for the UI, or the calendar will look like a FoodShare feed.
- `X-PUBLISHED-TTL:PT1H` so hourly is the publisher's own suggested cadence. Per club feeds: `/ical/rit/ical_club_<CLUBID>.ics`.

### 7.4 RIT Drupal events (better than expected, no scraping)

Previous research said "Drupal, no machine readable feed, scraping only." **That is wrong.** Drupal's JSON:API module is publicly exposed.

- `https://www.rit.edu/jsonapi/node/event` returns 200 `application/vnd.api+json`, 50 per page, about 450 events total, standard JSON:API cursor links (`links.next`, `links.last`).
- Useful attributes: `title`, `body`, `field_start_date`, `field_start_time`, `field_end_date`, `field_end_time`, `field_building`, `field_room_location`, `field_event_type`, `field_featured_event`, `field_image_url`, `field_image_alt_text`, `field_link`, `path`, `created`, `changed`.
- Supports JSON:API filtering and sparse fieldsets, so we can request only what we need and cut payload size.
- The index at `https://www.rit.edu/jsonapi` lists 61 resource types. Also potentially useful later: `node--athletics_event`, `node--facility`, `node--news`, `node--student_club`, `taxonomy_term--club`.
- **This promotes rit.edu events from "low priority scrape" to "low effort structured source."** It is the official events feed, and it complements CampusGroups (official university events vs student club events). Merge both, dedupe on title plus start time.

### 7.5 SHED makerspace (public GraphQL, real time)

`make.rit.edu` is an Apollo GraphQL API at `POST https://make.rit.edu/graphql`, `content-type: application/json`.

- **No auth.** `currentUser` returns `null` and everything else still resolves.
- **Introspection is disabled** in production, so read the schema from the open source repo instead: `github.com/rit-construct-makerspace/access-control-server`, under `server/src/graphql/schemas/`. It is actively maintained (last push 2026-08-19).

**Real time equipment availability, verified working:**

```graphql
{ equipments { id name subName inUse numAvailable numInUse archived room { id name } } }
```

Returns 56 live pieces of equipment across 10 rooms (Wood Shop 15, Manual Shop 9, Textiles 6, Electronics 6, Atrium 3D Print Farm 7, South Metal Shop 5, Laser Cutting 3, 3D Printing 2, Vinyl Cutting 2, Other 1). At capture time: 6 in use, 45 available. `allEquipment` is the same but includes archived items, so prefer `equipments`.

**Makerspace hours:**

```graphql
{ makerspaces { id name subtitle location description hours { day open close closed } } }
```

Gotcha to verify before shipping: `hours[].day` came back as a full ISO timestamp rather than a weekday name, and `closed` was `true` on every row while the space is presumably open. Treat this feed as **unreliable for hours** until confirmed. Equipment availability looked correct and is the valuable part. Cross check hours against `rit.edu/shed`.

Other schema files worth reading if we expand: `makerspacesSchema.ts`, `makerspaceHoursSchema.ts`, `equipmentInstanceSchema.ts`, `announcementsSchema.ts`, `roomsSchema.ts`.

### 7.6 maps.rit.edu occupancy (works, but awkward)

**The endpoint TigerDine uses is dead.** `maps.rit.edu/proxySearch/densityMapDetail.php?mdo=123` now 404s. The site was rewritten as a Remix/React Router app with Mapbox.

Current path: `GET https://maps.rit.edu/details/<mdoId>.data` returns 200 as `text/x-script`, about 225 KB, in **Remix turbo-stream format** (a flat, reference compressed array, not plain JSON). Also `GET /building/<buildingId>.data`.

Decoded, it contains exactly what we want:

```json
"densityData": {
  "count": 152, "max_occ": 150, "open_status": "Open Now",
  "location": "The_Cafe_&_Market_at_Crossroads", "building": "89", "mdo_id": 123,
  "intra_loc_hours": [ {"hour":0,"today":4,"today_max":5,"one_week_ago":4,"one_week_ago_max":4,"average":4}, ... ]
}
```

`intra_loc_hours` is a 24 hour series with today, same hour one week ago, and an average, which is enough for a proper "how busy is it right now vs typical" chart.

**The catch:** turbo-stream is a JavaScript format with no maintained Python decoder. This is an open decision, see section 8.

### 7.7 FD MealPlanner (menus, allergens, dietary) INTEGRATED 2026-08-30, CORRECTED 2026-08-30

**This is the only source with allergen and dietary data.** Verified across 771
recipes at one location:

```
ALLERGENS  Gluten 561, Wheat 561, Milk 515, Egg 406, Soy 399, Coconut 101,
           Treenut 41, Sesame 20, plus "May Contain Traces of ..." variants
DIETARY    Vegetarian 678, Vegan 128, Pork 40, Beef 5
```

**Halal and kosher are not tagged at all.** Nothing may ever be labelled either,
and filtering on the pork tag as a proxy would be wrong. A test asserts neither
string can appear.

**Rules, because this is about what people can safely eat:**
- Tags are stored and shown **verbatim**. Never tidied, merged, or inferred.
  "May Contain Traces of Milk" stays weaker than "Milk".
- A dietary filter **demotes, never deletes**. A hidden dish is
  indistinguishable from one that was never published.
- A flagged allergen **marks** a dish, it does not remove it.
- Every menu carries a caveat that these describe ingredients, not preparation,
  and say nothing about shared fryers or surfaces.

**Cadence: on demand, today only, cached until the date changes.** Corrected
2026-08-30, when this was first run against the live API. Three things were
wrong at once, each hiding the next.

**1. `startDate` and `endDate` were always sent empty**, so every fetch pulled a
whole month. Measured at Gracie's:

```
whole month, one meal period    25.9 MB     6.9 s
one day,     one meal period      1.0 MB     0.6 s
```

A month is 26 times the data, not the 7 MB previously recorded here, and Gracie's
publishes two meal periods, so showing one day's dishes was going to cost about
52 MB. Filling in the two date parameters is the whole fix.

**2. Meal periods are per location, not global.** The scraper asked every
location for period 8, FD's "All Day", assuming all of them publish against it:

```
RITZ         Breakfast, Lunch, Dinner, All Day
Gracie's     Breakfast, Lunch, Dinner
Crossroads   Lunch
```

Asking for a period a location does not have returns an empty result rather than
an error, so **most locations silently had no menu at all.** Query
`/{tenant}/mealPeriods?LocationId={id}` first and fetch each period. Gracie's
went from 0 dishes to 6,252.

**3. Seven of twelve location ids were wrong.** They had been assumed to run
1..12 in name order. The real ids skip numbers, and RITZ, The Commons and The
College Grind have an `accountId` that differs from their `locationId`:

```
   1/1   Artesano      4/4   Brick City    10/10  Gracie's     14/4   RITZ
   2/2   Beanz         6/6   Ctrl Alt DELi 11/11  Loaded Latke 15/14  The Commons
   7/7   Crossroads    8/8   GV Patio      12/12  Midnight Oil 18/17  College Grind
```

This failed in the worst possible way: the wrong ids were still **valid** ids,
so RITZ was served Gracie's menu **and Gracie's allergens** rather than failing.
`client/test/fd_mapping_test.dart` now pins the mapping against a captured copy
of the live location list.

FD location ids are its own and unrelated to TigerCenter's. The mapping lives in
`client/assets/config/fd_locations.json`. Three arena concessions have no
TigerCenter counterpart and are listed under `unmapped` so a future reader knows
they were considered.

### 7.7.1 Original recon notes

Confirmed live, no auth:

- Locations: `https://locations.fdmealplanner.com/api/v1/location-data-webapi/search-locationByAccount?AccountShortName=RIT&pageIndex=1&pageSize=0` returns `{operationId, success, errorMessages, data: {result: [{locationId, accountId, tenantId: 20, locationName: "RIT - Artesano Bakery & Cafe", locationCode, ...}]}}`.
- Meal periods: `https://apiservicelocatorstenantrit.fdmealplanner.com/api/v1/data-locator-webapi/20/mealPeriods?LocationId=<id>`
- Meals: `.../20/meals?menuId=0&accountId=<id>&locationId=<id>&mealPeriodId=<id>&tenantId=20&monthId=<m>&...`
- Tenant id for RIT is `20`. Location ids here are **FD's own**, unrelated to TigerCenter `id` or `mdoId`, so a name based mapping table is needed. Expect this to be the fiddliest integration.
- Lower priority than dining hours: visiting chefs and specials already come from TigerCenter. FD is for full menus and nutrition detail.

### 7.8 Reference repos: reuse vs rewrite

| Repo | Verdict | Why |
|---|---|---|
| `NinjaCheetah/TigerDine` | **Read, do not port** | Swift/SwiftUI, useless as code for us, but the single best documentation of which feed powers which feature. Its URL list confirmed `dining-all`, `dining-single`, the FD MealPlanner endpoints, and the (now dead) maps density path. `Shared/Components/TigerCenterParsers.swift` is worth reading for how it resolves the hours recurrence model and splits visiting chef names. Also copy its disclaimer and privacy posture. |
| `Lontronix/Dining-API` | **Rewrite, do not fork** | BeautifulSoup HTML scraping of the dining website, and the deps are from 2020 (Flask 1.1.2, Werkzeug 1.0.1, Jinja2 2.11.2). All of it is obsolete now that `dining-all` returns clean JSON. Its Dockerfile is the only mildly reusable part and we would write a better one anyway. |
| `mufasa159/rit-dining` | **Skip entirely** | Scrapes `rit.edu/dining/menus` with aiohttp for visiting chefs. TigerCenter gives us visiting chefs as structured data, so the whole premise is superseded. |

Net: **no code gets reused.** All three are valuable as documentation and dead ends already mapped. The good news is the recon replaced two HTML scrapers with two clean JSON APIs.

### 7.9 Campus mail: zone based, verified 2026-08-28

Authoritative source: `https://www.rit.edu/fa/campus-post-offices`, linked from
`rit.edu/parentsandfamilies/mail-and-care-packages`. Read the real page text, do not infer this.

**RIT runs a zone based mail system. There are no per hall street addresses and no mailbox numbers.**

- **"Mail and packages are picked up at the post office counter; physical mailboxes are not in use."** Students get an email notification per item, then collect at the counter with their RIT ID. Any design involving a mailbox number is wrong.
- **`1 Lomb Memorial Drive` is explicitly not a student package address.** The page states packages sent there "will experience delays". Never use it.
- Line 2 of the address carries a building/room or apartment designator, and **its format varies by housing area**. On order forms it goes in the second street address line.

**Two post offices, split east and west:**

| Office | Side | Street | Contact |
|---|---|---|---|
| Global Village Post Office | west | `6000 Reynolds Drive, Rochester NY 14623` | 585-475-3463, gvpostoffice@rit.edu |
| DSP Post Office | east | `43 Greenleaf Court, Rochester NY 14623` | 585-475-2518, postoff@rit.edu |

DSP is in the lower level of Fredericka Douglass Sprague Perry Hall, across from the Corner Store. Global Village is between Advantage Federal Credit Union and Shop One.

**Area to office mapping, with the line 2 format and RIT's own worked example:**

| Area | Office | Line 2 format | Example |
|---|---|---|---|
| Residence Halls | DSP | `Building, Room #` | `Peterson 1234` |
| Perkins Green | DSP | `Perkins Green Apartment #` | `PG 133-C` |
| Global Village | GV | `GV Building # Room #` | `GV 400 1020` |
| Greek Houses | GV | `House Room #` | `ASA 6011` |
| Riverknoll | GV | `RK Apartment #` | `RK 123` |
| University Commons | GV | `UC Apartment #` | `UC 123` |

**Two locations bypass the campus post offices entirely.** Mail goes straight to the property:
- RIT Inn: `5257 W Henrietta Rd, Henrietta NY 14467`
- 175 Jefferson Road: `175 Jefferson Rd, Rochester NY 14623`

**Post office hours are per service, not per office.** Package pickup and the shipping window run different hours, and both change between summer and fall. Fall 2026 hours begin Aug 22. Captured in `client/assets/config/post_offices.json` with a `service` field on each rule.

**Config shape that follows from this:** two offices with addresses and hours, six housing areas mapping to an office plus a line 2 format, and two direct delivery locations. Not fourteen halls with fourteen addresses.

### 7.9.1 Other static data

- SHED hours stay hardcoded, because the make.rit.edu hours feed is broken. Open and close times were read off that payload, but the weekday mapping is inferred, so treat as provisional and cross check against `rit.edu/shed`.
- All static config carries `last_verified` and is validated by pydantic at boot.

---

### 7.9.2 Things written off once, and what actually worked (2026-08-30)

A first pass ruled several of these out. Re-checking with different endpoint
shapes found two of them were reachable after all. **Do not treat the first "no
feed exists" as settled without trying a second shape.**

| Source | First verdict | Actual |
|---|---|---|
| **Athletics** | dead: `node--athletics_event` empty, Sidearm JSON 404s | **WORKS.** `ritathletics.com/calendar.ashx/calendar.ics` is a plain iCal, 182 fixtures, Sep to Mar. `calendar.json` 404s but `.ics` does not. Now a third event source |
| **Water fountains** | unknown, `categories.data` 404s | **WORKS.** `maps.rit.edu/categories/35.data` is Sustainability and holds **96 hydration stations** with building abbreviation and floor |
| Map kiosks / printing / ATMs | unknown | **Reachable, and the menu is now readable.** Category ids are in the hundreds, not 1 to 45. Every response embeds the whole category menu, and `decodeTurboStream` reads it, so searching one payload names them. Confirmed: 259 Retail, 236 Study Area, 279 Lactation Rooms, 11 Parking, 35 Sustainability, and **199 Workday time clocks under parent 39 Employees, integrated 2026-08-30 with 62 clocks, each with a real Point plus building, floor, room and RIT's clock id**. Then **527 Printers, 528 Connection Hub, 211 Computer Labs, 236 Study Areas, 279 Lactation Rooms, 87 Vending, 83 Convenience Stores, all integrated 2026-08-30 at no extra request**, because their parents (47, 27, 7) were already being fetched and every point in them was being parsed and dropped for want of a registered kind. Parent 47 alone was yielding zero. Then 440 Confidential support services (9), 452 FoodShare (1), 449 Bottle and can return (1), and, by adding parent 31 Better Me Wellness, 183 Higi health kiosks (3) and 187 Gyms (2). **25 kinds are now claimed and every sub-category the menu names is either claimed or empty.** 39 and 31 are the only parents fetched purely for pins; every other kind rides a request the app was already making |

**The whole category tree is readable in one request.** `decodeTurboStream` on any `categories/<id>.data` yields every parent and sub with its `parent_id`, so there is no need to guess ids again. Eleven parents: 3 Buildings, 7 Dining, 11 Parking, 15 Transportation, 19 Public Safety, 23 Accessibility, 27 Amenities, 31 Better Me Wellness, 35 Sustainability, 39 Employees, 47 Other.
| Library hours | dead | **Still dead.** LibCal says "No Locations for Opening Hours found", and `/library/hours`, `/library/about/hours` and `/library/wallace-center-hours` all 404 |
| Laundry | dead | **Still dead.** No vendor referenced anywhere, and no Drupal page has "laundry" in the title |
| Elevator status | dead | **Still dead.** No Drupal page has "elevator" in the title. Email only, as reported |

### 7.10 Drupal facility data (gate task, verified 2026-08-28)

Question asked: do any Drupal resource types carry facility or building hours, locations, open status, or post office info, enough to replace the static config?

**Answer: no. Keep the static config.** Details below.

Scope note: `/jsonapi` exposes **225 resource types**, not 61. The 61 figure was the `node--` plus `taxonomy_term--` subset. All 60 reachable node and taxonomy types were probed for fields matching hour/open/close/address/building/location/room/phone.

**Only `node--facility` carries anything relevant.** 466 records.

| Field | Populated | Shape |
|---|---|---|
| `facility_location` | 401 / 466 | free text, `{value, format: plain_text, processed}` |
| `facility_hours` | 123 / 466 | free text HTML, `{value, format: full_html, processed}` |
| `facility_type` | 449 / 466 | array, one of Educational, Lab, Research, Recreational, Center, Dining, Service, Sponsored |
| `facility_map_location` | **0 / 466** | relationship exists but is empty everywhere, so there is no maps.rit.edu join key here |

**Why the hours are not usable as structured data:**

- 123 populated values collapse to only **38 distinct strings**, and 61 of those are the identical generic boilerplate `7 a.m.-12 a.m.`. It is building envelope boilerplate, not real per facility hours.
- The field is a prose blob. Real values include `24/7 swipe card access &nbsp;`, `Swipe Access Required`, `Visit the Fitness and Recreation site for details.`, `Monday-Friday  9:00&nbsp;a.m. to 4:30 p.m.  Saturday-Sunday  Open by appointment`.
- **No per weekday structure, no open/close fields, no date exceptions, no holiday handling, no timezone.** Same information gap the static config exists to fill.
- Formatting is inconsistent across entries (`8 am - 5 pm` vs `8 a.m.-5 p.m.` vs `Monday - Sunday 7 a.m.-11 p.m.`), plus stray `&nbsp;` and `\r\n`.

**The specific records wanted are empty:**

- **Global Village Post Office** exists (`facility_type: ["Service"]`, location `Global Village`) but **`facility_hours` is empty.** Perry Hall post office has no record at all.
- **All 19 `Dining` facilities have empty hours**, except two irrelevant ones (a stock ticker display and a wine display). TigerCenter stays the dining source.
- **No SHED building record.** Only `Foundations Classroom (The SHED)`, a classroom, with empty hours.
- **No residence hall mailing addresses anywhere** in any resource type.

**What is still worth taking from `node--facility`:** it is a usable 466 entry campus facility directory (name, building/room string, type, description, main site URL). Good for a browse and search "what is in this building" feature later. It is not an hours source. Low priority.

**Faculty office hours exist but are out of scope.** `node--person` (5212 records) has `person_office_hours`, `person_office_address`, `person_office_location`, `person_phone`. That is individual staff contact data, not facilities. Not building it, and not caching personal data we do not need.

**Bonus find, a real join key for events.** `node--student_club` has 754 records with `field_student_club_campusgroup_l` pointing at `https://campusgroups.rit.edu/<SLUG>/`. That slug **matches the iCal `X-CG-CATEGORY=club_acronym` value on 60 of 60 distinct acronyms in the feed.** So club acronym from the iCal joins cleanly to an official club name. Use it to render proper organizer names and to power the group/collapse/mute UI.
Caveat, unverified: the sibling field `field_student_club_closed` is `1` on many clubs that look active (for example `RIT 365 Facilitators`). Its meaning is unknown, possibly closed membership rather than defunct. **Do not filter on it** without checking.


## 8. Decisions (settled 2026-08-28)

1. **Occupancy stays, as a targeted Python parser.** No Node sidecar, a second runtime for one endpoint is bad ops. Do **not** write a general turbo-stream decoder. Extract only `count`, `max_occ`, `open_status`, and the 24 hour series from `maps.rit.edu/details/<mdoId>.data`. One isolated module, fixture backed test, well under 150 lines. Wrap it so a parse failure hides the occupancy chip rather than failing the whole dining response. Live occupancy is a headline feature.
2. **Events: one merged table with a `source` field** (`campusgroups` / `drupal`). **No dedupe for MVP**, the point is to observe the real overlap before writing fuzzy matching. `organizer` is a first class column so sources can be grouped, collapsed, or muted (FoodShare is 213 of 921 events). Join organizer to `node--student_club` via the club acronym for display names.
3. **Makerspace: ship equipment availability, hardcode SHED hours.** Their hours feed returns `closed: true` on every row with an ISO timestamp where a weekday belongs, which is a bug in their data, not something to parse around. SHED hours live in the same static JSON config as post office hours.
4. **Static config confirmed necessary** by the section 7.10 gate task. Post office hours, SHED hours, and residence hall mailing addresses are all hand maintained JSON with a `last_verified` date.
5. **Walking paths come from OpenStreetMap, bundled as an asset, not fetched.**
   Decided 2026-08-30. maps.rit.edu publishes **no line geometry anywhere**: all 11 reachable categories are Point or Polygon, so the map could draw buildings and pins but nothing showing how you get between them.

   `scripts/fetch-osm-paths.py` pulls the network once from Overpass and writes `client/assets/map/paths.json`. It is an asset rather than an upstream because the walking network does not change, and because section 3.1 requires the app to work with no network on a first launch. A path you can only see after a successful fetch is exactly the thing that fails while you are standing outside.

   Size is deliberate: 2089 raw ways at 1.4 MB become **1216 footpaths and 608 roads, 5453 nodes, 114 KB**, by clipping to campus and simplifying at 2.2m, which is below what anyone can see at campus zoom. Coordinates are stored at 5 decimal places (about 1.1m) to match.

   **The data is ODbL, so the credit is an obligation.** It ships in the asset header and on the about screen, and a test fails if either is removed. Rerun the script when campus changes and commit the result.


## 9. Repo layout

```
client/                  the app, and the only thing that ships
  lib/data/              the scrapers, cadence, and storage
    sources/             one file per upstream
    upstream.dart        the single outbound client, sets the User-Agent
    local_backend.dart   routes a path to a source, holds the cadence
    store.dart           snapshots on disk, one JSON file per source
    hours.dart           the TigerCenter recurrence resolver
    campus_time.dart     America/New_York without a timezone package
    turbo_stream.dart    the general decoder, for the campus map graph
    campus_paths.dart    the bundled OSM walking network
  assets/config/         hand maintained JSON, each with a last_verified
  assets/map/            paths.json, generated by scripts/fetch-osm-paths.py
  test/golden/           the backend's own output, pinned
  test/fixtures/         captured upstream payloads
assets/generated/        the wordmark, glyphs and icon art, plus SPEC.md
docs/backlog.md          decided but not built
docs/recon/              captured sample payloads from recon
```

`backend/` was the FastAPI server. It is gone; see section 3. Its behaviour
survives as the golden files in `client/test/golden/`.

## 10. Android

Added 2026-08-30. The project was created Linux only, so `client/android/` did
not exist at all even though section 3 always named Android as a target.

**Configured and committed:** application id and namespace `dev.colewiz.tigerhub`
(the same string as the Linux window class), label `TigerHub`, launcher icons at
all five densities generated from the 512px master, and the `INTERNET`
permission.

**That permission is the one to remember.** Flutter writes it into the debug and
profile manifests only. A release build without it launches, shows its empty
state, and fails every scrape with nothing to explain why. `client/test/
android_readiness_test.dart` fails if it is ever dropped.

**Following the wallpaper is hidden off Linux**, not merely disabled. It reads a
scheme file a desktop shell writes; Android has no such file and no `HOME` to
look under, so the row could never do anything.

**Not built yet, deliberately.** There is no JDK and no Android SDK on this
machine, and installing them is about 1.5 GB of system-wide toolchain, which is
not worth installing until the build is actually wanted. `scripts/android-setup` reports exactly
what is missing and the pacman lines to fix it. Nothing in the repo needs
changing when the toolchain arrives:

```bash
scripts/android-setup              # what is still missing
cd client && flutter build apk --release
```
