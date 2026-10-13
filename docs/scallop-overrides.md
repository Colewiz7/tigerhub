# Scallop overrides

Places where TigerHub deliberately departs from the scallop-ui spec
(`.agents/skills/scallop-ui/references/spec.md`). The spec itself is not edited.
One line per override: rule, what we do instead, why.

- **Drag handles appear on hover and focus** -> the handle exists only in edit
  mode, and in edit mode it is keyboard-focusable with a visible focus indicator.
  Why: a handle that cannot drag outside edit mode is misleading. Decided by the
  owner 2026-10-13.
