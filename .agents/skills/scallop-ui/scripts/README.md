Rebuilt from the appendix of references/spec.md (the original script was lost). Run `npm ci` once here (exact versions pinned in package.json and package-lock.json: material-color-utilities 0.3.0, culori 4.0.2), then `node scallop-palette.mjs "#RRGGBB" [--write [dir]]`.

Checked against the spec: every dark role for seed #F76902 matches reference-dark exactly (primary, surfaces, text, ok, bad, warn).

CVD difference from the spec. Worst status-mark pair per simulation (Machado 2009, full severity, CIEDE2000, via culori), seed #F76902:

| | protan | deutan | tritan |
|---|---|---|---|
| dark, this script | 11.1 (ok/warn) | 11.2 (ok/warn) | 22.1 (bad/warn) |
| dark, spec says | 17.1 | 12.6 | 27.0 |
| light, this script | 14.9 (ok/warn) | 9.3 (ok/warn) | 11.4 (bad/warn) |
| light, spec says | 14.9 | 9.3 | 11.4 |

Light matches exactly. Dark is lower here than the spec quotes (the spec's 12.6 equals this script's dark ok/bad deutan, so the spec may have measured a different pair set). Every number clears the 8.0 floor. The spec was not edited.
