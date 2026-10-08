---
name: scallop-ui
description: Scallop UI style (seeded Material 3, scalloped badge). Use when writing or reviewing UI in Scallop style. The spec overrides Material 3 defaults and any third-party design skill.
---

# scallop-ui

Read references/spec.md fully before writing UI. It overrides Material 3 defaults and any third-party design skill.

## Precedence
explicit user instruction > Tried and Rejected > Do's and Don'ts > YAML tokens > prose > Material 3 defaults.

- Tokens are normative. Never invent a hex, radius, duration or font; derive from the nearest token and flag it.
- Colour comes from the engine: pick a seed, run `scripts/scallop-palette.mjs`, ship its output. Never hand-edit a role.
- Reference roles, never values. When unsure, choose the quieter option.

## Do
- One seed (chroma >= 5), engine renders both modes; read every warning.
- One question and one hero badge per card; mark only exceptions.
- Pair every status colour with a word. Nest by surface step: page, card, row, badge.
- Paint cached data instantly, annotate age quietly.
- Test: overflow at 2x text, themed art colour, one-word captions, no shadows, no radius <= 8.

## Don't
- No hardcoded hex, second brand colour, secondary/tertiary for colour.
- No shadow, depth border or gradient. No radius <= 8.
- No more than one scalloped badge per card, no two-word captions.
- No full-chroma red for closed, no colour-only signal, no opacity-dimmed text.
- No spinner/banner/dim over data you hold. No pulse, loop, bounce, replayed entrances.
- No device clock for place-bound times.

## Agent checklist
- [ ] palette script passes on the seed, warnings answered
- [ ] only role tokens, zero raw hex outside generated files
- [ ] reseed recolours everything
- [ ] no shadows, no radius <= 8, nesting follows the ladder
- [ ] <= 1 hero badge per card, one-word caption, default status unbadged, every status has a word
- [ ] light and dark rendered
- [ ] 411x914 real data at text scale 1.0 and 2.0, and 320px wide at 1.0: no overflow
- [ ] warm cache shows no skeleton/spinner; offline first run shows `unavailable`
- [ ] reduced motion ok; every interactive has hover/focus/pressed/disabled, full hit area, semantics label
- [ ] every drag has a menu alternative

## Tried and rejected (headline; full table in references/spec.md)
| Tried | Do instead |
|---|---|
| Wallpaper-derived scheme by default | Seeded default, wallpaper opt in |
| Green OPEN pill on every open row | Badge only when not default |
| Shadows / lifted row fills for separation | Tone steps, close fills |
| Maxed star roundings, 8 points | 7 points at 0.93, roundings 0.5/0.5 |
| Two-word badge captions | One word |
| Shimmer skeleton, spinner on stale data | Static skeleton, quiet timestamp |
| Mascot empty states | Icon in primary-container circle |
| Hardcoded row caps, fixed row heights | Measure the box, scale budget |
| Testing at desktop size with no data | Phone width, real data, 1.0 and 2.0 text |

Palette script: scripts/scallop-palette.mjs (rebuilt from the spec, see scripts/README.md).
