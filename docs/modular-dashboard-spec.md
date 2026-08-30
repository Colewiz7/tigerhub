# Modular Today dashboard

References:

- `assets/generated/mockups/modular-dashboard-light.svg`
- `assets/generated/mockups/modular-dashboard-dark.svg`

## What modular means

A card is an instance of a module type. The user can add more than one instance
of the same type, give each instance its own scope, choose among supported
sizes, reorder it or remove it.

This is intentionally not a freeform canvas. Pixel resizing and arbitrary
placement create holes, fragile phone layouts and difficult keyboard behavior.
Modules use a small set of footprints and the app packs them in reading order.

## Module instance model

Each saved card instance needs:

- A stable instance ID, separate from its module type.
- Module type.
- Scope configuration.
- Size choice.
- Position in reading order.
- Optional display preferences owned by that module type.

The current saved list of four string IDs should migrate to four default
instances without changing their order or hidden state.

## Sizes

Expose only sizes the selected module supports:

| Size | Desktop footprint | Intended content |
|---|---:|---|
| Compact | 1 column, 1 height unit | One answer or the next item |
| Standard | 1 column, 2 height units | Current card density |
| Wide | 2 columns, 1 or 2 height units | Calendar, map or grouped feed |

Sizes describe priority, not fixed pixels. On a one-column phone all sizes are
full width. Compact remains shorter, while standard and wide retain their
content depth. A wide card never causes horizontal scrolling.

Do not offer a size whose content cannot remain useful. Mailing Address does
not need Compact. A week calendar should default to Wide and may omit Compact.

## Initial module library

| Module | Scope options | Sizes |
|---|---|---|
| Dining status | All dining or one dining category | Compact, Standard |
| General events | All campus, event type or organizer | Compact, Standard, Wide |
| Club events | One organizer | Compact, Standard, Wide |
| Calendar | All visible events or one organizer | Standard, Wide |
| Visiting chefs | Campus-wide | Compact, Standard |
| Mailing address | Home area or chosen housing area | Standard |
| Facility hours | One gym, pool or makerspace | Compact, Standard |
| Campus map | Places, events or a saved category | Wide |

General events and club events may share one renderer, but they are different
module templates in the Add Card flow. This makes the common single-club task
clear without forcing every user through an advanced scope editor.

## Customize flow

1. `Customize` enters edit mode and opens a persistent inspector on wide
   screens or a bottom sheet on narrow screens.
2. Selecting a card exposes its type, scope, supported sizes and remove action.
3. `Add card` opens the module library, then asks only for configuration that
   module requires.
4. Dragging changes reading order. Keyboard users get Move earlier and Move
   later actions with the same result.
5. Changes preview immediately and persist as one dashboard configuration.

Keep remove inside the inspector and card edit affordance. Do not place a
destructive control over the card's primary action when edit mode is off.

## Packing rules

- Determine the available column count using the existing width, height and
  widow avoidance behavior.
- Pack instances in saved reading order using first fit into the current row.
- A wide module starts on the next row when two adjacent columns are not
  available. Do not reorder later cards around it just to fill a hole.
- If the final row has one standard card in a three-column layout, reduce the
  layout to two columns when that gives a more balanced result. Preserve the
  current no-widow behavior.
- Repacking for a window resize changes placement only. It never rewrites the
  saved order.

This produces predictable keyboard and screen-reader order, and it survives a
tall desktop window without creating a three-card row followed by one widow.

## Card content by size

Compact cards answer one question. Examples are `6 open now`, `Next event at
7:00 PM` or `Pool closes at 10:00 PM`.

Standard cards keep the current headline plus bounded preview list.

Wide cards may show a week calendar, grouped event columns or the map. They
must still have one clear headline and a bounded height.

## Accessibility and motion

- Edit mode must be announced, and every card exposes its position and size.
- Reorder actions need spoken confirmation.
- Scope controls use visible labels, not icons alone.
- Animate only the affected cards during repacking, using the established
  short easing. With reduced motion, cards move directly to their final slots.
- Focus stays on the edited card after size or scope changes.

## Delivery order

1. Introduce instance-based persistence and migrate the four current cards.
2. Add the inspector and the three size contracts.
3. Convert the current four cards into module templates.
4. Add scoped general events and single-club events.
5. Add calendar, facility and map modules.

This order proves the modular model before multiplying card types.

