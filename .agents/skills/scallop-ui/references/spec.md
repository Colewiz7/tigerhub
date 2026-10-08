---
version: beta
name: Scallop
description: Seeded Material 3 in the Caelestia spirit. Any one colour, rendered as a whole calm scheme by a validated colour engine. Flat tonal depth, soft big radii, and one scalloped badge per card holding the number that matters. A glanceable utility, not a dashboard.
colors:
  engine: { generator: material-color-utilities 0.3.0, scheme: tonal-spot, spec: "2021", contrast-level: 0, script: scallop-palette.mjs }
  seed: "#F76902"   # reference seed only. Any seed with HCT chroma >= 5 works.
  palettes:         # HCT hue and chroma. The seed's own chroma and tone are discarded.
    primary:         { hue: seed,      chroma: 36 }
    secondary:       { hue: seed,      chroma: 16 }
    tertiary:        { hue: seed + 60, chroma: 24 }
    neutral:         { hue: seed,      chroma: 6 }
    neutral-variant: { hue: seed,      chroma: 8 }
  tones:            # role: [dark, light], HCT tone (= CIELAB L*)
    primary: [80, 40]
    on-primary: [20, 100]
    primary-container: [30, 90]
    on-primary-container: [90, 30]
    surface-lowest: [4, 100]
    surface: [6, 98]
    surface-container-low: [10, 96]
    surface-container: [12, 94]
    surface-container-high: [17, 92]
    surface-container-highest: [22, 90]
    on-surface: [90, 10]
    on-surface-variant: [80, 30]
    outline: [60, 50]
    outline-variant: [30, 80]
    error: [80, 40]
  status:           # HCT anchor hue nudged 10% toward the seed hue; chroma fixed; tones pinned
    ok:   { hue: 152, chroma: 53, tone: [78, 54], text-tone: [78, 40] }
    bad:  { hue: 23,  chroma: 42, tone: [62, 30], text-tone: [62, 30] }
    warn: { hue: 74,  chroma: 44, tone: ["90 to 94", 44], text-tone: ["90 to 94", 44] }
    container: { tone: [30, 90] }
    on-container: { tone: [90, 10] }
  categorical:      # fixed, seed-independent. [dark, light]
    cat-1: ["#4392c9", "#2a7cbc"]
    cat-2: ["#7b5db0", "#694b92"]
    cat-3: ["#b45827", "#973e08"]
    cat-4: ["#6a9844", "#527e2b"]
  reference-dark:   # seed #F76902, for eyeballing only. Never copy these into code.
    surface-lowest: "#140c09"
    surface-container-low: "#221a16"
    surface-container-high: "#322824"
    surface-container-highest: "#3d332e"
    on-surface: "#f0dfd8"
    on-surface-variant: "#d7c2b9"
    primary: "#ffb693"
    on-primary: "#542104"
    primary-container: "#703717"
    ok: "#8cd375"
    bad: "#da7c71"
    warn: "#ffddb7"
opacity:
  hover: 0.08
  focus: 0.10
  pressed: 0.10
  dragged: 0.16
  disabled-container: 0.12
  disabled-content: 0.38
  header-tint: 0.14
  badge-tint: 0.32
  badge-tint-quiet: 0.20
  scrim: 0.60
  divider: 0.35
typography:
  display-lg:  { fontFamily: Rubik, fontSize: 68px, fontWeight: 300, lineHeight: 1.0,  letterSpacing: -0.022em, fontFeature: '"tnum" 1' }
  display-md:  { fontFamily: Rubik, fontSize: 46px, fontWeight: 300, lineHeight: 1.05, letterSpacing: -0.017em, fontFeature: '"tnum" 1' }
  time-hero:   { fontFamily: Rubik, fontSize: 36px, fontWeight: 300, lineHeight: 1.1,  fontFeature: '"tnum" 1' }
  badge-value: { fontFamily: Rubik, fontSize: 0.34 x badge, fontWeight: 500, lineHeight: 1.0, fontFeature: '"tnum" 1' }
  badge-label: { fontFamily: Rubik, fontSize: 0.135 x badge, fontWeight: 700, lineHeight: 1.1, letterSpacing: 0.05em, fontFeature: '"case" 1', textTransform: uppercase }
  title-lg:    { fontFamily: Rubik, fontSize: 27px, fontWeight: 600, lineHeight: 1.2,  letterSpacing: 0.004em }
  title-md:    { fontFamily: Rubik, fontSize: 18px, fontWeight: 500, lineHeight: 1.3 }
  body-md:     { fontFamily: Rubik, fontSize: 17px, fontWeight: 400, lineHeight: 1.4 }
  body-sm:     { fontFamily: Rubik, fontSize: 14.5px, fontWeight: 400, lineHeight: 1.35 }
  label-sm:    { fontFamily: Rubik, fontSize: 12.5px, fontWeight: 500, lineHeight: 1.2, letterSpacing: 0.088em }
  wordmark:    { fontFamily: Space Grotesk, fontWeight: 700 }
rounded:
  small: 14px
  inner: 20px
  card: 30px
  full: 9999px
  scallop: { points: 7, inner-radius: 0.93, point-rounding: 0.5, valley-rounding: 0.5 }
spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  card-padding: 26px
  gutter: 10px
  row-gap: 8px
  badge-gap: 13px
  pill-y: 6px
  pill-x: 13px
  input-y: 18px
  input-x: 20px
  group-gap: 6px
  content-max: 900px
  column-max: 560px
  side-panel: 320px
  card-height-min: 344px
  card-height-max: 560px
  two-column-from: 1240px
  reflow-min: 320px
motion:
  ease-out: cubic-bezier(0.215, 0.61, 0.355, 1)
  swap-out: 140ms
  select: 160ms
  swap-in: 180ms
  surface: 240ms
  value: 260ms
  stagger: 20ms
  stagger-count: 6
  state-layer: 140ms
components:
  page:             { backgroundColor: "{colors.surface-lowest}" }
  card:             { backgroundColor: "{colors.surface-container-low}", rounded: "{rounded.card}", padding: "{spacing.card-padding}", elevation: 0 }
  row:              { backgroundColor: "{colors.surface-container-high}", rounded: "{rounded.inner}", height: 64px, gap: "{spacing.row-gap}", padding: 8px 12px }
  row-badge:        { shape: circle, size: 42px, backgroundColor: "{colors.primary} @ {opacity.badge-tint}", iconColor: "{colors.primary}", iconSize: 18px }
  row-closed:       { badge: "{colors.on-surface-variant} @ {opacity.badge-tint-quiet}", iconColor: "{colors.on-surface-variant}", titleColor: "{colors.on-surface-variant}", opacity: 1 }
  group-header:     { backgroundColor: "{colors.primary} @ {opacity.header-tint}", textColor: "{colors.primary}", typography: "{typography.title-md}", rounded: "{rounded.small}", height: 40px, padding: 8px 12px }
  hero-badge:       { shape: "{rounded.scallop}", size: 88px, backgroundColor: "{colors.primary}", textColor: "{colors.on-primary}", textScaleMax: 1.3 }
  hero-badge-quiet: { backgroundColor: "{colors.surface-container-highest}", textColor: "{colors.on-surface}" }
  pill:             { backgroundColor: "{colors.surface-container-high}", textColor: "{colors.on-surface-variant}", typography: "{typography.body-sm}", rounded: "{rounded.full}", padding: 6px 13px, hitTarget: 48px touch / 40px pointer }
  button-filled:    { backgroundColor: "{colors.primary}", textColor: "{colors.on-primary}", typography: "{typography.title-md}", rounded: "{rounded.full}", height: 48px, padding: 0 24px }
  button-tonal:     { backgroundColor: "{colors.primary-container}", textColor: "{colors.on-primary-container}", typography: "{typography.title-md}", rounded: "{rounded.full}", height: 48px, padding: 0 24px }
  input:            { backgroundColor: "{colors.surface-container-high}", textColor: "{colors.on-surface}", typography: "{typography.body-md}", rounded: "{rounded.inner}", border: none, padding: 18px 20px, focusBorder: "1.5px {colors.primary}" }
  tab:              { iconSize: 29px, typography: "{typography.label-sm}", indicator: "34x3 pill, {colors.primary}" }
  sheet:            { backgroundColor: "{colors.surface-container-low}", rounded: "{rounded.card} top", padding: "{spacing.card-padding}" }
  empty-mark:       { shape: circle, size: 58px, sizeFullPanel: 76px, backgroundColor: "{colors.primary-container}", iconColor: "{colors.on-primary-container}", iconSize: 29px }
  arc-progress:     { sweep: 260deg, gap: bottom, stroke: 9px at 92px, caps: round, track: "{colors.surface-container-highest}" }
  segmented-bar:    { width: 54px, height: 6px, segments: 2, gap: 4px }
  focus-ring:       { width: 2px, offset: 2px, color: "{colors.primary}", radius: element + 2px }
---

# Scallop

> Any one colour, rendered as a whole scheme. Flat, soft and quiet, with **one scalloped cookie per card** holding the only number you came for.

**Agents (Codex, Claude Code): read this whole file before writing UI.**

- **Precedence:** explicit user instruction > Tried and Rejected > Do's and Don'ts > YAML tokens > prose > Material 3 defaults.
- **Tokens are normative.** Never invent a hex, radius, duration or font. If something is missing, derive it from the nearest token and flag it in your summary.
- **Colour comes from the engine.** Pick a seed, run `scallop-palette.mjs`, ship its output. Never hand-edit one role.
- **Reference roles, never values.** `primary`, never `#ffb693`. The YAML hexes are one rendering, not the palette.
- **When unsure, choose the quieter option.** Fewer badges, fewer words, less motion.
- Start from the engine output (`tokens.css`, `tokens.json`), then this file.

## Overview

**Personality:** friendly, warm, calm. A well-made noticeboard you check between things, not a control room. Warmth comes from shape, voice and softness, so it survives any seed.

**The blend:** Material 3 roles and tonal surfaces, read through the Caelestia shell: rows that sit barely above the page, bright circular icon badges, pills everywhere, and colour generated rather than picked.

**Audience:** everyone, on a phone, for four seconds. Glanceability beats density.

**Principles**

1. **One scheme, rendered.** The whole UI is one seeded palette. No second brand colour, no per-widget picks.
2. **One question per card.** Every card answers one question, and its hero badge is that answer.
3. **Mark the exception, not the rule.** Default state gets no badge. Only what is different is decorated.
4. **Depth through tone, never shadow.** Shadows are disabled globally.
5. **Words beat colour, and words beat clocks.** Status always carries a word. "until midnight" beats "11:59 PM".
6. **Cached is instant.** Data you already hold paints at full opacity immediately. Loading UI exists for first run only.

**Signature details** (what makes it Scallop, not stock M3)

- The seven-lobed scalloped badge: one per card, a big number, a one-word caption.
- Rows as their own soft containers, anchored by a bright 42px circular icon badge.
- An oversized, light (300) number set against small, muted, wide-tracked labels.
- Closed and past things recede into neutral instead of turning red.
- Tabs with a 3px accent underline and no pill, like an editor's tab strip.
- A partial-sweep arc and a two-segment bar instead of stock progress indicators.

## Colors

### The engine (why any colour works)

Scallop never picks colours. It picks **one seed** and renders it through Material's HCT colour space: hue and chroma from CAM16, tone equal to CIELAB L* ([Material, The Science of Color & Design](https://material.io/blog/science-of-color-design)).

**What the engine keeps and throws away**

- **Keeps the seed's hue.** That is the identity.
- **Throws away the seed's chroma and tone.** Primary is always chroma 36, neutrals 6 and 8. A neon seed and a dusty seed of the same hue render the same calm scheme. This is why it stays elegant every time.
- **Pins every role to a tone.** Tone is perceptual lightness, so contrast is a tone difference: about 50 apart for 4.5:1, 40 apart for 3:1 ([same source](https://material.io/blog/science-of-color-design)).

**Seed rules**

- **Chroma ≥ 5.** Below that, hue is noise and the scheme hue is arbitrary: grey `#808080` renders a cyan primary. The threshold is Material's own colourfulness cutoff (`Score.CUTOFF_CHROMA = 5`, material-color-utilities source).
- **Hues 90 to 111 need an eye check.** Light-mode primary at tone 40 lands in the dark-yellow band Material's `DislikeAnalyzer` flags (hue 90 to 111, chroma > 16, tone < 65), which reads olive. The script warns; it doesn't fix.
- **Pin the generator.** `@material/material-color-utilities@0.3.0`, `SchemeTonalSpot`, spec 2021, contrast level 0. The 2025 spec darkens dark surfaces (surface `#130d0a` vs `#1a120e` for the reference seed), so switching specs is a redesign, not an upgrade.

**Workflow**

1. `node scallop-palette.mjs "#RRGGBB"` prints every gate.
2. All gates pass and warnings are read: `--write` emits `tokens.css` and `tokens.json` (DTCG 2025.10 colour format).
3. Look at it in both modes. The script checks numbers; you check taste.

### Surfaces

Surfaces come from the neutral palette (seed hue, chroma 6), so every grey leans toward the seed. Steps are small: rows sit only a little above the card, and the icon badges carry the contrast.

| Token | Tone dark / light | Use |
|---|---|---|
| `surface-lowest` | 4 / 100 | Page canvas, tab bar, map background |
| `surface` | 6 / 98 | Full-screen covers, base under scrims |
| `surface-container-low` | 10 / 96 | Cards, sheets |
| `surface-container` | 12 / 94 | Rare: a panel between card and row |
| `surface-container-high` | 17 / 92 | Rows, inputs, pills, skeleton rows |
| `surface-container-highest` | 22 / 90 | Quiet hero badge, arc and bar tracks |
| `on-surface` | 90 / 10 | Primary text, hero numbers |
| `on-surface-variant` | 80 / 30 | Subtitles, labels, inactive tabs and icons |
| `outline` | 60 / 50 | High-contrast input borders only |
| `outline-variant` | 30 / 80 | Map edges; dividers at 0.35 alpha (rare) |

- **The nesting ladder is fixed:** page `lowest` → card `low` → row `high` → badge `highest` or `primary`. Skip at most one step.
- **No borders for depth.** A surface step always does it better.
- **No `#000` or `#fff` in dark mode.** The tone table already guarantees it.

### Primary (the seed)

| Role | Tone dark / light | Use |
|---|---|---|
| `primary` | 80 / 40 | Filled hero badge, row badge tint, tab underline, group header text, focus |
| `on-primary` | 20 / 100 | Text on the filled badge |
| `primary-container` | 30 / 90 | Empty-state mark, selected map feature, tonal button |
| `on-primary-container` | 90 / 30 | Icon and text on the above |

**Primary is allowed on:** the hero badge, row badges (`badge-tint` fill, full-strength glyph), group header strips (`header-tint`), the tab underline, one filled button per view, progress, focus, links.

**Primary is banned on:** body text, card backgrounds, status, and any categorical series. The seed is taken: a hundred primary-coloured things read as a hundred selected things.

**Secondary and tertiary** exist because the engine makes them. Scallop doesn't use them. Don't reach for them to add colour.

### Status

Status is its own role family: never the categorical palette, never `error` for "closed". It starts from recognisable green, red and amber, **nudged 10% of the way toward the seed hue**, with chroma fixed and tones pinned so the three separate by **lightness** as well as hue.

| Role | Means | HCT anchor | Chroma | Tone dark | Tone light |
|---|---|---|---|---|---|
| `ok` | Open now, available | 152 | 53 | 78 | 54 (mark), 40 (text) |
| `bad` | Closed, down | 23 | 42 | 62 | 30 |
| `warn` | Busy, over capacity | 74 | 44 | 90, rising to 94 only if the CVD gate needs it | 44 |

- **Two grades per role.** `ok` is the mark (glyph, dot, pill fill), held to 3:1. `ok-text` is the word, held to 4.5:1. They are equal everywhere except light `ok`, where the word needs tone 40.
- **Containers** (banners only): `*-container` tone 30 / 90, `on-*-container` tone 90 / 10, same hue and chroma.
- **Validated, reference seed:** status marks ΔE2000 protan 17.1, deutan 12.6, tritan 27.0 (dark); 14.9, 9.3, 11.4 (light). Across 13 seeds spanning the hue circle, every mark stays ≥ 8.0 in all three simulations and every word ≥ 4.5:1 on cards and rows. Simulation: Machado, Oliveira and Fernandes 2009 at full severity, via [culori](https://culorijs.org/).
- **Never colour alone.** Every status ships its word: `OPEN · until 9:00 PM`.
- **Closed recedes.** Closed is terracotta (chroma 42), not alarm red. See Row for how a closed row steps back.
- **The dark amber is pale on purpose.** Deepening it drops its separation from green to ΔE 2.0 in protanopia.
- **Containers are for banners only.** A resting status is the coloured word or a small pill, not a filled strip.
- **Re-run the script after any change.** Looking at it is not validation.

### State layers

A translucent layer of the content colour over the component. No ink splash: the state layer is the whole feedback, as in Caelestia. Values match Material 3's state layer opacities.

| State | Opacity |
|---|---|
| Hover | `hover` 0.08 |
| Focus | `focus` 0.10 |
| Pressed | `pressed` 0.10 |
| Dragged | `dragged` 0.16 |
| Disabled | container `on-surface` @ 0.12, content @ 0.38 |

The layer fades over `state-layer` (140ms) with `ease-out`.

### Light mode

Generated from the same seed with the same roles and the tone table above. It is a first-class mode: every screen is rendered and checked in both.

### Following an external scheme (optional)

Taking colour from the OS wallpaper or a desktop shell's scheme file is **opt in, off by default**, and always has a visible way back to the seed. External files often put their container roles a few points apart, so re-derive the ladder by blending `surface-tint` over `surface` at 0.28 / 0.38 / 0.50 / 0.65 for low to highest.

### Data visualization

- **Categorical, fixed order, never cycle:** `cat-1` blue, `cat-2` purple, `cat-3` rust, `cat-4` olive. Seed-independent.
- **Validated all pairs, not just neighbours,** because colour follows the entity and any two can meet. Worst pair ΔE2000: dark deutan 8.5, protan 14.1, tritan 13.7; light deutan 8.3, protan 13.6, tritan 14.8. Every category ≥ 3:1 on cards.
- A fifth category folds into "Other". Colour follows the entity, never its position.
- **Prefer one series plus a sentence** over two series in scheme colours.
- Bars: `primary` for "now", `primary` at reduced alpha for the rest, 2px gap, rounded data ends, square at the baseline. Label only the ends and "now".
- Carry category on the edge and keep the fill neutral. Always a legend that names every family.
- If the script warns that a category sits within ΔE 10.9 of primary, never show that category beside primary in one chart.

## Typography

**Families**

- **Rubik** (variable, `wght` axis): all UI. Bundled, never fetched, so it works offline.
- **Space Grotesk** (bold): the wordmark only.
- **Material Symbols Rounded**: icons.

**Rules**

- **The hero is oversized and light.** `display-*` at 300. Everything around it recedes.
- **Except inside the badge.** On a saturated fill 300 reads hairline, so the badge value is 500 and its caption 700.
- **Labels under numbers are small, muted, wide tracked** (`label-sm`, 0.088em).
- **Tracking is in em,** so it scales with the user's text size. Each value is the old px value divided by its font size (1.1 / 12.5 = 0.088em).
- **Hierarchy by size and weight contrast, not colour.** Don't bold body text to make it important; make its neighbours quieter.
- **Uppercase is a signal, used in three places only:** the badge caption, the status word in a subtitle (`OPEN`, `CLOSED`, `ENDED`), and tab labels. Everything else is sentence case. Uppercase text turns on Rubik's `case` feature so punctuation sits at cap height.
- **Badge captions are one word.** `OPEN`, `DAYS`, `EVENTS`, `TODAY`, `LEFT`. At 88px there is room for about six capitals; more clips and reads as off centre.
- **Numbers:** `tnum` on anything that updates, including every `display-*`. Rubik's default figures are proportional (advance widths 398 to 618 units), so a ticking number jitters without it. Never truncate a number.
- **Times are words where words are clearer:** `midnight`, `noon`, `until 9:00 PM`, `opens Mon 7:00 AM`.
- **Truncation:** row titles and subtitles are one line with ellipsis; the full string stays in the row's accessible name. Card bodies never clip without a `+N more` pill.
- **`on-surface-variant` is for single lines.** In dark mode it measures APCA Lc 68 to 71 on cards and rows: fine for a subtitle, too low for a paragraph.

## Layout

**Spacing:** a 4px scale plus named tuned values: `card-padding` 26, `gutter` 10, `badge-gap` 13, `pill-y` 6, `pill-x` 13, `input-y` 18, `input-x` 20, `group-gap` 6. Nothing else off-scale.

**Padding order:** always vertical then horizontal (`8px 12px` = 8 top and bottom, 12 left and right).

**Proximity:** row gap 8, row internal 8 vertical / 12 horizontal, badge to text 13, card title to content 12, group header gap 6.

**Window classes**

| Width | Card grid | Lists | Jump rail |
|---|---|---|---|
| < 700px | 1 column | 1 column | Hidden |
| 700 to 1239px | 2 to 3 columns | 1 column, max 900 | Shown |
| ≥ 1240px | 3 to 4 columns | 2 columns, max 560 each, items dealt alternately | Shown |

- **The grid packs by height too.** Prefer a layout whose cards land between `card-height-min` 344 and `card-height-max` 560 and whose last row is full. Four cards in a tall window go 2×2, never 3 plus a widow.
- **Cards fill the box they are given.** Content is bounded by measurement, never by a hardcoded item count.
- **Nothing is cut off without being counted.** Withheld rows become a `+N more` pill that navigates to the full view.
- **Measure the container, not the window.** A tab under a masthead is never the window's width.
- **Touch targets:** 48px on touch, 40px on pointer. **Visual size may be smaller; the hit area never is.** A 32px pill still answers taps across 48px.
- **Wide windows use the width without longer lines.** Two columns past 1240, never a 2000px line.
- **Reflow down to 320px wide** without horizontal scrolling, the width WCAG 1.4.10 uses for 400% zoom ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/reflow)).
- **Drag handles appear on hover and focus,** in space that is always reserved so the title never shifts. Every drag has a non-drag path: Move up and Move down in the item's menu ([WCAG 2.5.7](https://tetralogical.com/blog/2023/10/05/whats-new-wcag-2.2)). On touch, reorder lives in the menu only.

## Elevation & Depth

**Tonal only. Shadows are off globally,** so no stray component can reintroduce one.

| Level | Surface | Examples |
|---|---|---|
| 0 | `surface-lowest` | Page, tab bar |
| 1 | `surface-container-low` | Cards, sheets |
| 2 | `surface-container-high` | Rows, inputs, pills |
| 3 | `surface-container-highest` / `primary` | Hero badge, tracks |

- **Overlap without shadow:** sheets and dialogs sit over a scrim (`surface-lowest` @ `scrim` 0.6), which separates them without a drop shadow.
- **No glow, no gradients, no blur.**

## Shapes

| Token | Radius | Used by |
|---|---|---|
| `small` | 14px | Group headers, small controls |
| `inner` | 20px | Rows, inputs, anything inside a card |
| `card` | 30px | Cards, sheet top corners |
| `full` | 9999px | Chips, buttons, pills, bars, tab underline |
| `scallop` | star, 7 points, 0.93 | The hero badge, map pins and clusters |

- **Nothing is rounded at 8 or below.** Small things become full pills instead.
- **Concentric when tight:** when a child sits within 12px of its parent's corner, inner radius = outer − padding. If that comes out at 8 or less, the corners don't read as a pair: use the scale.
- **The scallop:** a rounded star with 7 points, inner radius 0.93, point rounding 0.5, valley rounding 0.5. The two roundings must sum to ≤ 1. It belongs to the same family as Material 3 Expressive's `Cookie7Sided` ([Android reference](https://developer.android.com/reference/kotlin/androidx/compose/material3/MaterialShapes)), with shallower lobes on purpose.
- **Circles are for icons. The scallop is for numbers.**

## Components

**Card**

- Title row: optional 22px section glyph, `title-lg` title, and the hero badge on the right so it costs no vertical space. A quiet freshness line under the title, only when stale or failing.
- Content 12px below, crossfading 140ms when it swaps.
- **One hero badge per card, max.** It answers the card's question ("6 open"), never a detail of one row.

**Hero badge**

- 88px default. Value `size × 0.34` at 500, caption `size × 0.135` at 700, full opacity.
- **Filled** (`primary`) when the number matters now; **quiet** (`surface-container-highest`) when present but not urgent, like a week with no events.
- **Text scale capped at 1.3 inside the shape.** The same figure is always stated in words nearby.
- One-word caption. No caption beats a two-word one.

**Row**

- 72px including the 8px gap, scaled with text size and clamped 1x to 2x.
- 42px circle badge at `primary @ badge-tint` with an 18px glyph. At 21px the ring gets too thin to read as a badge.
- Title `title-md` one line, subtitle `body-sm` one line, trailing capped at 132px so it can never starve the title.
- Default status (open, no sensor) gets no trailing pill. Only rows with something to say get one.
- **Closed and past rows step back without losing contrast:** the badge turns neutral (`on-surface-variant @ badge-tint-quiet`, glyph 5.2:1 dark, 5.6:1 light), the title drops to `on-surface-variant`, there's no trailing pill, and the row sorts after the live ones. No opacity on text. No divider marks the boundary; order and emphasis do.

**Group header:** `primary @ header-tint` strip, `small` radius, 17px icon, `title-md` in primary (7.4:1 dark, 4.8:1 light on the reference seed), count on the right in `body-sm` at weight 400, same colour. Quieter by size and weight, not opacity. It is a landmark, not a footnote.

**Pills:** full radius, `surface-container-high`, `body-sm` at 500. The `+N more` pill carries a 15px chevron when it navigates. Interactive pills get the full hit area.

**Buttons:** full pills, 48px on touch. One filled per view, then tonal, then text. Sentence case, verb first.

**Inputs:** filled `surface-container-high`, `inner` radius, no border at rest, 1.5px `primary` border on focus. Label above in `label-sm`, and a placeholder or value is always visible inside: that text is what identifies the field, so no boundary is required ([W3C, 1.4.11 boundaries](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast)).

**Dropdowns:** a split control. A wide pill holds the value; a separate small `primary` pill holds the chevron.

**Tabs:** 29px icon over an uppercase `label-sm` label, with a 34×3 `primary` underline on the active tab that scales in from the centre. Inactive is `on-surface-variant`. No pill, no box.

**Jump rail:** long grouped lists get a left rail with one shared active marker that slides 180ms. Dropped below 700px.

**Sheets:** details open as a bottom sheet on narrow windows, a `side-panel` (320px) on wide ones. Top corners `card` radius.

**Progress:** Arc progress is a 260° sweep with the gap at the bottom, round caps and a darker track. Segmented bar is two segments with a 4px gap, never one continuous bar. Stock spinners never appear.

**Empty states:** a 58px `primary-container` circle (76px on a full panel) with a familiar rounded icon, one plain sentence in `body-md`, an optional `body-sm` line and an optional action. No apology, no mascot scene.

**Offline and source-down are statuses, not empty states.** They sit beside cached content at full opacity and never replace it.

## Data States

Every data surface is in exactly one of six states. Treat this as a contract.

| State | Meaning | Shows |
|---|---|---|
| `priming` | First run, no cache, loading | Static content-shaped skeleton: 42px circle, bars at 70 / 52 / 38% width, 64px rows. No shimmer. |
| `unavailable` | First run, no cache, load failed | The empty-state layout with a cloud-off icon, `Can't load this yet`, and a tonal `Try again` button |
| `ok` | Fresh | Content. Nothing else. |
| `stale` | Cached, older than the source's `stale-after` | Content at full opacity + `updated 5m ago` in `on-surface-variant` |
| `failing` | Cached, refresh errored | Content at full opacity + `updated 5m ago` in `error` with a 12px cloud-off icon |
| `empty` | Loaded, nothing to show | The empty state |

- **Every source declares `stale-after`.** There's no global default; the product decides per source.
- **The skeleton must not move the final layout** by more than 8px.
- **Never a spinner, banner or dim layer on `stale` or `failing`.**
- **Pull to refresh really refreshes:** it forces every source, with a one-minute floor per source.

## Motion

**Philosophy:** short, interruptible and functional. Motion shows that a value changed. It is never decoration on a screen someone glances at for four seconds.

**Easing**

| Token | Curve | Use |
|---|---|---|
| `ease-out` | `cubic-bezier(0.215, 0.61, 0.355, 1)` (ease-out cubic) | Everything |

No bounce, no spring overshoot, no second curve.

**Durations:** 140 (out, state layers), 160 (small selection), 180 (in, the default), 240 (large surface), 260 (value interpolation). No single animation runs longer than 260ms; no sequence ends later than 280ms.

**Choreography**

| Interaction | Duration | Animates |
|---|---|---|
| Hover, focus, press | 140ms | state-layer opacity |
| Text or status value changes | 140 out, 180 in | opacity crossfade |
| Hero badge first value | 180ms | opacity + translateY 3px → 0 |
| Hero badge changes | 260ms | count to the new value, only if units and meaning are unchanged |
| Arc progress | 260ms | sweep from the previous value |
| Tab switch | 180ms | content crossfade; underline scaleX 0 → 1 |
| Jump rail marker | 180ms | position |
| Detail sheet | 240ms | enter; a shared-element move only for the one badge or image |
| Map pin select | 160ms | fill + scale 0.96 → 1 |
| Copy confirmation | 160ms | icon swap, scale 0.94 → 1 |
| First list paint | 180ms each, +20ms stagger, first 6 rows (ends by 280ms) | opacity. First successful load only |
| Skeleton → content | 140ms | crossfade. Parts never stagger |

**Rules**

- **Only changed values animate.** A refresh that returns the same numbers is invisible.
- **Never replay an entrance** on refresh, tab return or resize.
- **Status never pulses.** Motion is not a label.
- **Animate paint, opacity and transform.** Never layout dimensions.
- **Retarget, don't queue.** A second update mid-animation starts from where the first one is.
- **Reduced motion:** everything that moves jumps to its end state (translate, scale, sweep, count-up, rail position). Opacity crossfades and state layers keep their durations, since fading moves nothing. Reduce means reduce, not none ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/Media_Queries/Using_Media_Queries_for_Accessibility)).
- **No full-screen loading cover** except over a genuinely cold, expensive build (a map's first open), and never over a warm cache.

## Iconography & Imagery

**Icons**

- **Material Symbols Rounded.** 18px in row badges, 24px default, 29px in tabs.
- **Custom glyphs carry section identity only:** section headers, section nav, map category pins, and that section's empty state. 24px, drawn in the current text colour, never tinted apart from their label.
- **Keep Material for** tabs, actions (copy, pin, close, search, settings) and rows whose glyph must tell kinds apart.

**The wordmark:** Space Grotesk, split at the internal capital. The first half carries `primary` with three horizontal, uneven, wavy markings clipped to its letters; the second half is `on-surface`. Ship the text as outlines. Wide mark from 230px, compact from 184px, monochrome for high contrast.

**Illustration:** none in the running UI. Empty states use the icon mark. The mascot belongs on the app icon and the about screen, not on "nothing today".

**Images:** rounded to their container's radius. The placeholder is seed-tinted art for that aspect ratio, never a grey flash.

## Content & Voice

- Plain, direct, a little warm. Sentence case, active voice, no exclamation marks, no apologies.
- **Say the state in the fewest true words:** `Open`, not `Open now` under a heading that already means now.
- **Say it honestly.** A closed place never gets a "quieter than usual" caption. A wrong map pin is worse than no pin, so say `N events mapped · M without a location`.
- Relative age: `just now`, `5m ago`, `3h ago`, `2d ago`.
- Empty copy: `Nothing scheduled today`, `Everything is closed right now`, `No matches`. Offline: `Showing saved data`. Unavailable: `Can't load this yet`.
- The middle dot joins a status word to its detail (`CLOSED · opens Mon 7:00 AM`) and nothing else.
- No em dashes anywhere.

## Accessibility

- **Contrast:** text ≥ 4.5:1, large text and marks ≥ 3:1, **measured on the surface the thing actually sits on**. The script checks every role pair on cards, rows and the highest surface.
- **APCA as a second opinion:** body text aims for |Lc| ≥ 75 ([APCA](https://github.com/Myndex/apca-introduction)). Advisory only, since APCA is a WCAG 3 candidate, not a standard.
- **Text scale:** everything works at 2.0x at 411px wide with real data. Fixed rows scale their budget; fixed shapes cap their text at 1.3x and restate the figure in words.
- **Colour vision:** status and categorical palettes are validated for protanopia, deuteranopia and tritanopia on every seed, plus a monochrome pass by eye.
- **Focus ring:** 2px `primary`, 2px offset, radius = element radius + 2px, keyboard focus only. Primary sits at ≥ 5.8:1 on cards in both modes for the reference seed, and the script gates it at 3:1 for every seed. A focused element is never covered by sticky UI ([WCAG 2.4.11](https://tetralogical.com/blog/2023/10/05/whats-new-wcag-2.2)).
- **High contrast preference:** `on-surface-variant` becomes `on-surface`, and inputs gain a 1px `outline` border at rest.
- **Semantics:** a row reads as one node (`title, subtitle`); decorative art is excluded; group headers are headers; loading areas are live regions with a real label (`Loading hours`).
- **Keyboard:** digits switch tabs, `Esc` closes sheets, and map gestures always have a list equivalent.
- **Back** walks home first and only leaves from the home tab.

## Performance

- **Paint from cache first.** Cold start renders the last snapshot before any network.
- **Inactive tabs are offstage:** not laid out, not ticking.
- **Build expensive geometry once** (map projection, label measurement, clustering), never per frame.
- **Cancel every subscription** on rebuild or dispose. Stale ones overwrite the current page.
- **Bundle fonts and art.** No runtime font fetches, no network images for chrome.
- **Generate colour at build time,** not on launch. The engine is a build step; the app ships its output.
- **Think before a dependency.** Most packages reached for here turned out to be 100 lines.

## Platform Mapping

Short mappings only. The substance lives above.

- **Web:** ship the generated `tokens.css`. Tailwind maps to the CSS variables, never hex. Sizes in `rem` (1rem = 16px) so they follow the browser's text size. Mixing uses `color-mix(in srgb, …)`, which matches alpha compositing everywhere else. Reduced motion is `prefers-reduced-motion: reduce`; high contrast is `prefers-contrast: more`. The scallop is an inline SVG path generated once from the star parameters.
- **Flutter:** `ColorScheme.fromSeed(seedColor: …, brightness: …)` produces the same roles as the engine (same library, same tonal-spot default). Status and categorical in a `ThemeExtension` filled from `tokens.json`. `splashFactory: NoSplash.splashFactory`, `shadowColor: Colors.transparent`. Scallop = `StarBorder(points: 7, innerRadiusRatio: 0.93, pointRounding: 0.5, valleyRounding: 0.5)`. Measure with `LayoutBuilder`. Reduced motion = `MediaQuery.disableAnimations`. Icons = `Icons.*_rounded`. Pass `SvgTheme` to every themed SVG.
- **Jetpack Compose:** `MaterialShapes.Cookie7Sided` is the stock relative; build Scallop's shallower lobes with `RoundedPolygon.star(7, innerRadius = 0.93f, …)`.
- **Caelestia / Quickshell (QML):** role names match 1:1. Easing: `Easing.BezierSpline` with `[0.215, 0.61, 0.355, 1, 1, 1]`. External scheme file: `~/.local/state/caelestia/scheme.json`; watch the directory, not the file, because the writer replaces it.
- **Linux desktop:** one instance per session (a second launch focuses the first). Hide client-drawn title bars on tiling window managers (Hyprland, sway, niri).
- **Android:** system back follows the Back rule in Accessibility.

## Tried and Rejected

Each of these shipped or was built, then pulled. Don't redo them.

| Tried | What happened | Do instead |
|---|---|---|
| Following the wallpaper by default | A scheme from someone's photo is a guess; sometimes unreadable, and it broke status colours | Seeded default; wallpaper opt in |
| Hue-harmonizing status toward the seed | Closed and busy measured ΔE 1.0 apart in deuteranopia. Looked fine, were the same colour | 10% hue nudge + pinned tones, validated |
| Full-chroma red for closed | Read as an alarm; a column of red at night | Chroma 42 terracotta, and the row steps back |
| A green OPEN pill on every open row | Thirteen identical pills drowned out the five that mattered | Badge only when not default |
| Lifting row fills for separation | About 3x too far; washed everything out | Keep fills close; let icon badges carry contrast |
| An external scheme's own container roles | A few points apart; nesting vanished | Blend `surface-tint` over `surface` |
| Two-series chart in scheme colours | primary vs on-surface-variant at ΔE 10.9 | One series and a sentence |
| Badge for one row's occupancy | That row usually wasn't on screen | Card-level hero |
| Maxing both star roundings (1.0 / 1.0) | Invalid geometry: the roundings overlap and the shape can't be built | 0.5 / 0.5; softness from geometry |
| 8 points at 0.90 | Read as an octagon; above 0.95 or 8 points it becomes a circle | 7 points at 0.93 |
| Weight 300 number inside the badge | Hairline on the fill; caption at 85% of 10px unreadable | 500 value, 700 full-opacity caption |
| Two-word badge captions | Wider than 88px; clipped and looked off centre | One word, enforced by a test |
| Dense first type scale (body 13.5) | Tuned to fit, not to read | Body 17, titles 27 |
| 21px glyph in a 42px badge | Ring too thin to read as a badge | 18px |
| Fixed row heights at text scale 1.0 | Every list overflowed at 1.3 | Scale the budget, clamp 1x to 2x |
| Text scaling freely inside the scallop | The number spilled out of the shape at 2.0 | Cap at 1.3, restate in words |
| Hardcoded row caps | One item stranded at the top of an empty card | Measure the box |
| Unconstrained trailing text | A 283px timestamp squeezed the title to zero | Trailing max 132px |
| Grid columns from width alone | One wide row with dead space below; 3 plus a widow | Pack by height and fullness |
| Cartoon mascot empty states | "Nothing today" felt like novelty art | Icon in a `primary-container` circle |
| Custom glyphs everywhere | Changed style without fixing repetition | Section identity only |
| Vertical wordmark stripes | Read as a barcode | Horizontal, uneven, wavy |
| Themed art without an explicit colour | The renderer fell back to black: black on black, no error | Always hand themed art the theme's colour |
| Live text inside a clip path | Some renderers drop it; the stripes floated over the letters | Flatten text to outlines; keep the clip flat |
| Spinner on stale data | Undid offline first | Quiet timestamp |
| Shimmer skeleton | Priming lasts about a second; the shimmer never finishes | Static skeleton |
| Loading cover on every tab switch | Covered warm tabs for no reason | Cold expensive builds only |
| Replaying list entrances on refresh | Every two-minute tick made the list dance | First paint only |
| A client-drawn title bar on a tiling desktop | A second title bar eating space | Let the window manager own the frame |
| Reading the device clock for place-bound times | Countdowns and "now" markers off by the timezone | Use the place's clock; tests pin the day |
| Testing at desktop size with no data | Empty states can't overflow, so it proved nothing | Phone width, real data, 1.0 and 2.0 text |

## Do's and Don'ts

**Do**

- Pick one seed with chroma ≥ 5 and let the engine render both modes.
- Run the script and read every warning before shipping a new seed.
- Give each card one question and one hero that answers it.
- Mark only the exceptions; let the default state stay quiet.
- Pair every status colour with a word.
- Nest by surface step: page, card, row, badge.
- Say times in words where words are clearer.
- Paint cached data instantly and annotate its age quietly.
- Guard the quiet failures with tests: overflow at 2x, themed art colour, one-word captions, no shadows, no radius ≤ 8.

**Don't**

- Don't hardcode hex, hand-edit a role, or pick a second brand colour.
- Don't use secondary or tertiary to add colour.
- Don't add a shadow, a border for depth, or a gradient.
- Don't round anything at 8 or below.
- Don't put more than one scalloped badge on a card, or two words under its number.
- Don't use full-chroma red for "closed", or colour as the only signal.
- Don't dim text with opacity; step it down a role instead.
- Don't show a spinner, banner or dim layer over data you already have.
- Don't cap rows with a guess; measure.
- Don't pulse, loop, bounce or replay entrances.
- Don't use a mascot or illustration where an icon and a sentence will do.
- Don't read the device clock for anything tied to a place.

## Agent Checklist

Before calling a screen done, verify:

- [ ] `scallop-palette.mjs` passes on the seed; warnings read and answered.
- [ ] Only role tokens used; zero raw hex outside generated files.
- [ ] Changing the seed and regenerating recolours everything correctly.
- [ ] No shadows, no radius ≤ 8, nesting follows the ladder.
- [ ] At most one hero badge per card; it answers the card's question; its caption is one word.
- [ ] Default status is unbadged; every status has a word.
- [ ] Rendered in light and dark.
- [ ] 411×914 with real data at text scale 1.0 and 2.0, and 320px wide at 1.0: no overflow, no sideways scroll.
- [ ] Warm cache: no skeleton, spinner or cover. First run offline shows `unavailable`, not an endless skeleton.
- [ ] Stale and failing paint at full opacity with the freshness line.
- [ ] Reduced motion: movement jumps, fades remain, everything renders.
- [ ] Every interactive element has hover, focus, pressed and disabled states, a full-size hit area, and a semantics label.
- [ ] Every drag has a menu alternative.

## Appendix: engine constants

| Constant | Value | Where it comes from |
|---|---|---|
| Scheme | tonal spot, spec 2021, contrast 0 | Reproduces the shipped reference exactly (every role matched) |
| Palette chroma | primary 36, secondary 16, tertiary 24 at hue + 60, neutral 6, neutral-variant 8 | material-color-utilities `DynamicScheme`, tonal spot |
| Min seed chroma | 5 | material-color-utilities `Score.CUTOFF_CHROMA` |
| Dislike band | hue 90 to 111, chroma > 16, tone < 65 | material-color-utilities `DislikeAnalyzer` |
| Status anchors | ok 152, bad 23, warn 74 | The shipped status hues with the 10% seed nudge undone: (h − 0.1 × 44.5) / 0.9 |
| CVD floor | ΔE2000 ≥ 8.0, all pairs, all three types | Just under the lowest separation the reference shipped (8.4) |
| Category vs primary | warn below ΔE 10.9 | The separation Tried and Rejected already found too close |

## Appendix: tokens.css (static part)

Colour variables come from the generated `tokens.css`. Everything else is fixed:

```css
:root {
  --r-small: 14px; --r-inner: 20px; --r-card: 30px; --r-full: 9999px;
  --pad-card: 26px; --gutter: 10px; --row-gap: 8px;
  --font: "Rubik", system-ui, sans-serif;
  --font-wordmark: "Space Grotesk", "Rubik", sans-serif;
  --ease-out: cubic-bezier(0.215, 0.61, 0.355, 1);
  --d-out: 140ms; --d-select: 160ms; --d-in: 180ms; --d-surface: 240ms; --d-value: 260ms;
}

body { background: var(--surface-lowest); color: var(--on-surface); font: 400 1.0625rem/1.4 var(--font); }
.card { background: var(--surface-container-low); border-radius: var(--r-card); padding: var(--pad-card); }
.row  { background: var(--surface-container-high); border-radius: var(--r-inner); padding: 8px 12px; }
.row-badge { width: 42px; height: 42px; border-radius: 50%;
  background: color-mix(in srgb, var(--primary) 32%, transparent); color: var(--primary); }
.row[data-closed] .row-badge { background: color-mix(in srgb, var(--on-surface-variant) 20%, transparent); color: var(--on-surface-variant); }
.row[data-closed] .title { color: var(--on-surface-variant); }
.pill { border-radius: var(--r-full); background: var(--surface-container-high); padding: 6px 13px; }
.pill[href], button.pill { position: relative; }
.pill[href]::after, button.pill::after { content: ""; position: absolute; left: 50%; top: 50%;
  width: max(100%, 48px); height: max(100%, 48px); translate: -50% -50%; }
.label { font-size: 0.78125rem; font-weight: 500; letter-spacing: 0.088em; color: var(--on-surface-variant); }
.caps  { text-transform: uppercase; font-feature-settings: "case" 1; }
.hero  { font-weight: 300; font-variant-numeric: tabular-nums; letter-spacing: -0.022em; }

.interactive { position: relative; isolation: isolate; }
.interactive::before { content: ""; position: absolute; inset: 0; z-index: -1;
  border-radius: inherit; background: currentColor; opacity: 0;
  transition: opacity var(--d-out) var(--ease-out); }
.interactive:hover::before { opacity: .08; }
.interactive:focus-visible::before,
.interactive:active::before { opacity: .10; }
:focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation: none !important;
    transition-property: opacity, color, background-color !important;
  }
}
@media (prefers-contrast: more) {
  :root { --on-surface-variant: var(--on-surface); }
  input, textarea, select { border: 1px solid var(--outline); }
}
```
