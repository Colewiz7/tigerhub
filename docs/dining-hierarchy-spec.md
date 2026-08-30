# Dining row hierarchy

This is the visual decision for `docs/codex-sheet.md` Task 6. It does not
change semantic colours or ordering.

## Decision

Open locations carry the useful visual weight. Closed locations recede and do
not repeat a red pill down the trailing edge.

| State | Title and icon | Subtitle | Trailing |
|---|---|---|---|
| Open, sensor available | Full emphasis, open accent | `OPEN · until 9:00 PM` | Occupancy pill |
| Open, no sensor | Full emphasis, open accent | `OPEN · until 9:00 PM` | Nothing |
| Closed, next opening known | Dimmed, neutral accent | `CLOSED · opens Mon 7:00 AM` | Nothing |
| Closed, schedule unknown | Dimmed, neutral accent | `CLOSED · hours unavailable` | Nothing |
| Pinned | Pin replaces venue glyph, emphasis still follows status | Same as status | Same as status |

The uppercase word in every subtitle is the non-colour status label. Removing
the closed pill therefore does not make colour the only signal. Occupancy stays
trailing because it is the only row-specific fact worth scanning vertically.

## Layout

- Keep the existing `StatusRow` height and spacing.
- Reserve no empty trailing column for rows without occupancy.
- Use the existing `onSurfaceVariant` dimming for closed title, icon, and
  subtitle. Do not introduce another grey or alter `semantic.closed`.
- The open/closed boundary comes from sort order and emphasis, not a divider.
- The Today card continues to show open rows first and uses its hero count as
  the summary.

Reference: `assets/generated/mockups/dining-hierarchy.svg`.

## Acceptance checks

1. At night, the list reads as quiet text rather than a red column.
2. If one location is open, it is the first and strongest row.
3. Every row still says `OPEN` or `CLOSED` in text.
4. Protanopia, deuteranopia, and monochrome previews preserve the hierarchy.
