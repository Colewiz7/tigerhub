# Generated asset handoff

Run `python3 scripts/generate-design-assets.py` to reproduce every SVG here.
All art uses transparent backgrounds unless the asset is explicitly a card
placeholder. No Flutter wiring or data-layer files are changed.

## Empty states

- Canvas: 200 x 140. Display at 112 x 78 in compact cards and up to 200 x 140
  in full-width empty panels.
- Layout: 20 px between illustration and copy, 8 px between title and optional
  action. Keep at least 24 px outer card padding.
- Copy: `Nothing scheduled today`, `Everything is closed right now`, `Showing
  saved data`, `This source is unavailable`, `No matches`, and `No visiting
  chefs today`.
- Offline and source-down are status states, not loaders. Existing cached
  content remains full opacity above or beside this notice.

## Wordmark

Use the wide mark when at least 230 logical pixels are available, compact at
184, and monochrome in high-contrast contexts. The SVG expects Space Grotesk,
then Rubik, then a sans-serif fallback. Convert text to paths before packaging
if exact cross-platform metrics are required.

## Glyphs

Render at 24 x 24 with `currentColor`. Do not scale stroke width independently.
The sprite contains symbols addressed by the filenames' base names.

## Dining placeholder

Choose the aspect ratio matching the card crop and select the light or dark
file from the active theme. The left half is deliberately quiet for overlaid
location text.
