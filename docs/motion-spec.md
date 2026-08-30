# TigerHub motion and priming specification

This is a design handoff, not Flutter wiring. It applies the backlog constraints
to the current components. The app is a frequently checked utility, so motion
is short, interruptible, and functional.

## Global rules

- Default duration: 180 ms with `Curves.easeOutCubic`.
- Large surface transition: 240 ms with `Curves.easeOutCubic`.
- Value interpolation: 260 ms with `Curves.easeOutCubic`, matching the jump
  list's established timing.
- No bounce, blur, ambient loop, delayed content, or queued animation.
- Animate paint, opacity, or transform. Do not animate layout dimensions.
- If either `MediaQuery.disableAnimationsOf(context)` or
  `accessibleNavigation` is true, paint the final state immediately.
- Cached `stale` and `failing` content always paints immediately at full
  opacity. Only `DataState.priming` receives a placeholder.

## Priming skeleton

Replace the centred spinner with a static, content-shaped skeleton. It should
already occupy the final card's approximate space, so data settles rather than
popping the card to a new height.

- Hero badge: one 76 px seven-lobed scallop at 12 percent opacity.
- Copy bars: 70, 52, and 38 percent of available width, 12 px tall, full-pill
  ends, 10 px gaps.
- Rows: two or three 44 px rows. Each has a 28 px circular glyph well and two
  pill bars. Match the card's actual density, not a generic loading template.
- No shimmer. Priming often lasts only one second, and a loop would begin but
  not resolve before content arrives.
- Transition to content with a 140 ms crossfade. Do not stagger skeleton parts.
- Reduced motion: replace the skeleton with final content instantly.

The reference mockup is `assets/generated/mockups/priming-skeleton.svg`.

## Motion matrix

| Surface | Trigger | Treatment | Reduced motion |
|---|---|---|---|
| Text or status value | Refresh changes value | 140 ms outgoing fade, replace, 180 ms incoming fade | Instant replace |
| Numeric hero badge | First real value after priming | Fade plus translate Y from 3 px, 180 ms | Final value immediately |
| Numeric hero badge | Refresh changes value | Interpolate only when units and meaning are unchanged, 260 ms | Instant replace |
| `ArcProgress` | First value or changed value | Tween prior sweep to new sweep, 260 ms | Paint new sweep immediately |
| Detail sheet | Row tap | Existing route transition; reserve `Hero` for the one badge or image, 240 ms | No shared-element travel |
| App tabs | Pointer or touch | 180 ms content crossfade; active indicator slides 180 ms | Indicator and content swap instantly |
| Jump rail marker | Scroll changes active group | Move a shared marker 180 ms; recolor text and icon with it | Instant marker position |
| First list paint | First successful load only | First 6 visible rows fade in, 20 ms stagger, 180 ms each | All rows visible immediately |
| Refresh | Any existing list | No row stagger and no whole-list transition | Same |
| Copy icon | Copy succeeds | Copy to check fade and scale 0.94 to 1, 160 ms | Instant check |

## Frequency decisions

- Scrolling, keyboard navigation, and repeated rail jumps receive no decorative
  motion beyond the functional position marker.
- Status chips never pulse. Colour and motion never replace their text labels.
- Empty-state mascot art remains still. It is normal content, not a reward.
- A list refresh does not replay its entrance sequence.

## Acceptance checks

1. Launch with a warm cache: no skeleton or spinner appears.
2. Launch with no cache: skeleton appears without changing final card height by
   more than 8 logical pixels.
3. Force a two-minute refresh: only changed values transition.
4. Trigger a second update before the first finishes: the animation retargets
   without queuing or flashing the old value.
5. Enable reduced motion and accessible navigation separately: every final
   state remains visible and usable.
