# Scallop overrides

Places where TigerHub deliberately departs from the scallop-ui spec
(`.agents/skills/scallop-ui/references/spec.md`). The spec itself is not edited.
One line per override: rule, what we do instead, why.

- **Drag handles appear on hover and focus** -> the handle exists only in edit
  mode, and in edit mode it is keyboard-focusable with a visible focus indicator.
  Why: a handle that cannot drag outside edit mode is misleading. Decided by the
  owner 2026-10-13.

- **No blur (exception #2)** -> on iOS only, the bottom tab bar is a floating
  glass capsule (one BackdropFilter, sigma ~20, surfaceContainer tint at ~70%
  alpha, 0.5pt hairline, no shadow). Android and Linux keep the opaque Material
  NavigationBar. Why: platform-native integration. Falls back to an opaque
  tinted capsule of the same shape if a real-iPhone profile shows jank.
  Decided by the owner 2026-10-14. Replaces the earlier "frosted top bar behind
  a flag" idea.

- **Measure the box, don't cap rows** -> on phones (under 600pt) a dashboard
  card previews a fixed number of rows (`phonePreviewRows` = 4 in
  `bounded_list.dart`, with the "+N more" row for the rest). Why: the owner's
  condense target ("Dining card 4 rows") makes card height equal its content,
  so there is no box to measure. Confirmed by the owner (round 4).
- **Card gap 10 on phones** -> the gap between dashboard cards is 10 under 600pt
  (`Insets.phoneCardGap`; 5 per cell side), where SKILL.md said "gutter 4". The
  4 is the row gap. Confirmed by the owner (round 4); the `scallop-ui` SKILL.md
  override line now says card gap 10, row gap 4.
