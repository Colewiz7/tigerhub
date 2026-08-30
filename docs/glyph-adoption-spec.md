# Section glyph adoption

The generated glyphs provide section identity. They are not a drop-in
replacement for every Material icon in the app.

## Use the custom glyphs for

- Campus section headers and navigation entries.
- Empty-state props when the same concept appears at a larger scale.
- The map's category pins and filter chips.
- The Visiting Chefs card header, where the toque is the section identity.

## Keep Material Symbols Rounded for

- Global tab navigation. Familiar platform-level destinations matter more than
  illustration consistency.
- Actions such as copy, pin, close, search, directions, expand, and settings.
- Dining venue rows. The generated `dining` glyph names the section but does not
  distinguish cafe, market, truck, ice cream, and restaurant.
- Event rows until category-specific event glyphs exist. Replacing one calendar
  with the same custom calendar would change style but not reduce repetition.

## Mapping

| Generated glyph | Primary use |
|---|---|
| `dining` | Dining section and map filter |
| `events` | Events section and event pins |
| `calendar` | Full calendar destination only |
| `housing` | Mailing Address section |
| `post-office` | Post office places and map pins |
| `makerspace` | Makerspace section and map pins |
| `buildings` | Campus buildings section and map filter |
| `market` | Market category header and pins |
| `visiting-chef` | Visiting Chefs section |

Render at 24 px with `currentColor`. Do not tint custom glyphs independently of
the label that they identify.
