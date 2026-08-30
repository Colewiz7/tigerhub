# Campus map design handoff

This resolves the UI and interaction half of `docs/codex-sheet.md` Task 8. The
map paints cached GeoJSON directly in TigerHub's theme. It does not use raster
tiles, an API key, or a new package.

## Entry and layout

- Add `Map` as a view within Campus, not a fifth global tab.
- Campus remembers the user's last `List` or `Map` choice for the session only.
- The map occupies the available pane. On wide windows, a 320 px result panel
  sits beside it. On narrow windows, results and details use the existing bottom
  sheet pattern.
- First-run `DataState.priming` uses the static map-shaped skeleton. Cached,
  stale, or failing geometry remains fully visible with the existing freshness
  line.

## Visual system

- Background: `surfaceContainerLowest`.
- Building polygons: `surfaceContainerHigh`, with a 1 px
  `outlineVariant` edge. Selected building: `primaryContainer`.
- Walkways and roads: quiet `outlineVariant` strokes. Do not imitate Google or
  Mapbox styling and do not add terrain texture.
- Place pin: 36 px seven-lobed scallop with a 20 px rounded section glyph.
- Cluster: 40 px scallop carrying a numeric count. It expands into individual
  pins when selected or zoomed.
- Event pin: primary scallop with a small calendar glyph. Dining occupancy uses
  the existing semantic open/busy colours and always includes text in details.
- Building abbreviations appear only when they fit without collision. They are
  supporting labels, not a dense cartographic layer.

Reference: `assets/generated/mockups/campus-map.svg`.

## Controls

- Top-left segmented control: `Places` and `Events`.
- Below it, horizontally scrolling filter chips from the existing categories.
  `All` is first. Selection is additive only if a single category proved too
  restrictive in testing; start with one active category.
- Top-right: `Fit campus` button. Do not add compass, tilt, satellite, traffic,
  or map-provider controls.
- Pointer wheel and pinch zoom around the focal point. Drag pans. Double tap or
  double click zooms one step. Keyboard plus/minus zooms without animation.
- Minimum zoom always keeps some campus geometry visible. `Fit campus` restores
  the initial bounds with 32 px padding.

## Selection and details

1. Selecting a pin highlights its building polygon where a join exists.
2. A wide layout updates the side panel. A narrow layout opens a bottom sheet.
3. Place details show name, building/room, short description, and live data
   already available for that category.
4. Event details show title, time, organizer, room, and source. The map does not
   invent a building when matching confidence is low.
5. Selecting a cluster fits its members. It never opens a list on the first tap.

## Event placement contract

- Exact building abbreviation, number, or normalized full-name matches may pin.
- Alias matches may pin only from a reviewed static alias table.
- Fuzzy matching may suggest candidates during development but may not place a
  production pin automatically.
- Unmatched events remain available in the Events list. The map header says
  `N events mapped · M without a location` when `M` is nonzero.
- A wrong pin is worse than no pin. No fallback pin at campus centre.

## Motion and accessibility

- Pin selection: 160 ms fill/scale transition from 0.96 to 1. No bouncing pin.
- Side-panel content: 180 ms crossfade. Rapid selection retargets rather than
  queues.
- Fit-campus: 240 ms ease-out only for pointer/touch input. Keyboard and reduced
  motion jump immediately.
- Every pin has a semantic label containing category, name, and building.
- Provide list-equivalent navigation in reading order. Map gestures cannot be
  the only way to reach a place.

## Acceptance checks

1. Airplane mode with a warm cache renders the complete map.
2. Point and Polygon features render in correct longitude/latitude order.
3. Light, dark, monochrome, and three colour-vision simulations preserve
   selection and category distinctions.
4. No label or pin is clipped at 200 percent text scaling.
5. The unmapped count equals the events omitted from the map.
6. Map selection and details are fully usable with keyboard and screen reader.
