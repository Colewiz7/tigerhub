# Project skills

Agent skills for this repo. C = Claude Code (`.claude/skills`), X = Codex (`.agents/skills`). Shared skills have one real copy in `.agents/skills` and a symlink in `.claude/skills`. Reviewed before install: SKILL.md and every script read, no network calls or credential access found (skill-creator style tooling not used here).

cole-code-style (global) wins over any skill here on comments and formatting. scallop-ui wins over material-3 and other design skills.

| Skill | Agent | Source | Commit | License |
|---|---|---|---|---|
| scallop-ui | C, X | local, ~/code/design-styles (material.md) | n/a | n/a |
| async-safety | C, X | zakariaf/Flutter-Skills | e073e5e | MIT |
| accessibility-as-code | C, X | zakariaf/Flutter-Skills | e073e5e | MIT |
| flutter-fix-layout-issues | C, X | flutter/agent-plugins | 0ef3972 | BSD-3-Clause |
| flutter-build-responsive-layout | C, X | flutter/agent-plugins | 0ef3972 | BSD-3-Clause |
| appstore-full-audit (+4 agents, 30 review skills, /appstore-detect) | C | cruisediary/apple-app-review-skills, install.sh --project | f9a746f | MIT |
| material-3 (audit only, `disable-model-invocation: true` added) | C | hamen/material-3-skill | 14385f2 | MIT |
| design-review-workflow | C | zakariaf/Flutter-Skills | e073e5e | MIT |
| variant-analysis | C | trailofbits/skills | 82fe822 | CC BY-SA 4.0 |
| flutter-add-widget-test | X | flutter/agent-plugins | 0ef3972 | BSD-3-Clause |
| widget-golden-and-a11y-testing | X | zakariaf/Flutter-Skills | e073e5e | MIT |
| local-notifications-scheduler | X | zakariaf/Flutter-Skills | e073e5e | MIT |
| testing-strategy | X | zakariaf/Flutter-Skills | e073e5e | MIT |
| dart-run-static-analysis | X | dart-lang/skills | 0d9f1c4 | BSD-3-Clause |
| dart-fix-runtime-errors | X | dart-lang/skills | 0d9f1c4 | BSD-3-Clause |

## MCP

Dart MCP server (`dart mcp-server`): `.mcp.json` for Claude, `.codex/config.toml` for Codex. Needs the Dart SDK on PATH (not verified, dart was not installed when this was set up).

## Not installed

dartdoc-conventions, frontend-design, zakariaf Riverpod, go_router and Drift skills, brainstorming, subagent-driven-development.

## Modified vendored files

- `.claude/agents/*.md` (the five cruisediary agents): added `name` and `description` frontmatter. Upstream files have none, so Claude Code did not load them as subagents.
- `scallop-ui` carries a project override: phones under 600pt use card padding 16, radius 24, gutter 4.

