# TigerHub design system

Portable. Nothing here depends on Flutter.

- `tokens.css`   drop into a web project, then use the variables. Light and
                 dark are both defined; dark is a `prefers-color-scheme` block
                 plus a `[data-theme="dark"]` block so a manual toggle works.
- `tokens.json`  the same values for anything that is not CSS.
- `STYLE.md`     the rules and the reasoning. Read this one.
- `preview.html` the system rendered as a camera monitor. Open it in a browser.

Generated from the app's own ColorScheme, so the values are what actually
ships rather than a transcription.

The seed is #F76902. It appears nowhere in the output on purpose: a seed is an
input to Material 3's algorithm, not a swatch. Change the seed and regenerate
to rebrand the whole set.
