# Post office hours hierarchy

References:

- `assets/generated/mockups/post-office-hours-light.svg`
- `assets/generated/mockups/post-office-hours-dark.svg`

## Decision

Keep the address first. Under it, render one self-contained module per service.
Package pickup and the shipping window must never be combined because they can
have different seasons, days and hours.

The module gives the large centred times a frame without turning them into a
table. It uses a quiet container, a narrow orange route marker at the left and
the existing post-office glyph in the office heading. The dotted route between
the address and service modules is decorative and may be omitted below 600 px.

## Anatomy

Each service module contains, in order:

1. Service name at `titleMedium` or equivalent.
2. Active season as a quiet text label aligned to the opposite edge.
3. One day caption, even when the day has a split shift.
4. Every time span for that day, centred and set at 32 to 40 logical pixels.
5. A short closed-days note when the published schedule provides one.

For a split shift, stack both spans under the same day caption. Put a small,
wavy divider between spans. Do not repeat the day and do not use a plus sign,
which can read as arithmetic or imply both spans happen simultaneously.

## Responsive layout

- Below 840 px, service modules stack vertically.
- At 840 px and above, two services may sit side by side.
- Each module needs at least 340 px of content width. If that cannot be met,
  stack them.
- Allow times to wrap only between the opening and closing span. Never split a
  clock value across lines.
- Extra services continue in reading order in the next row.

## Colour and type

- Use existing theme roles only.
- Office surface: `surfaceContainerLow`.
- Service surface: `surfaceContainerHigh`.
- Route marker and glyph: `primary`.
- Times: `onSurface`.
- Day, season and closed notes: `onSurfaceVariant`.
- The wavy split marker uses the warm stripe colour already used by the
  wordmark, but it is decoration and cannot carry meaning alone.

## Accessibility

- Read each service as one semantics group: service, season, days, then spans.
- Decorative route and divider paths are excluded from semantics.
- Preserve the published day and time text. Colour and placement are not a
  substitute for labels.
- At large text scale, stack the season below the service name and allow the
  module to grow vertically.

## Motion

No ambient motion. If the active season changes while the screen is open, use
the existing short content fade. Reduced motion swaps immediately.

