# TigerHub Omnigent policy module

Custom [Omnigent](https://omnigent.ai) policies for the shell tool. **Not enabled anywhere**: nothing in
this repo's settings or config references it. Review first.

## What is in it

| Piece | File | Behaviour |
|---|---|---|
| `deny_policy` | `policies.py` | DENY: anything touching `*codemagic_api*` (any tool, any argument; by name, and by `realpath`/`samefile` against the configurable `credentials_path`, so a symlink to it is caught), `sudo`/`doas`, `rm` with recursive+force (`-rf`, `-fr`, `-r -f`, `--recursive --force`, `--no-preserve-root`), `git push` (also via `git -C/-c ...`, `-c alias.*`), `gh pr merge/create/close`. Sees through `;`/`&&`/`\|`/newlines, `VAR=x` prefixes, quoting, absolute paths, `$(...)`/backticks, `bash -c`, `eval`, `env`/`timeout`/`xargs`/... wrappers. |
| `allow_policy` | `policies.py` | ALLOW exactly one plain `flutter`/`dart` build-test-analyze-format command or `pub get` (`pub upgrade`/`add`/`remove`/`outdated`/... are not allowed and never reach the judge, so they ASK) or read-only `git`/`gh` command. Character whitelist: no `; & \| < > $ \` ( ) \\`, no newline, no globs, no env prefix, no absolute binary path. |
| `make_judge_policy` | `policies.py` | LLM judge. Can only return ALLOW or `None`; never DENY. Prompt says repo/web text is untrusted data. Strict JSON parse; error/timeout means `None`. Has a call limit and a cost cap. |
| `make_gate` | `policies.py` | The thing to register: deny, then allow, then judge, then an **explicit ASK**. |

## Deviation from the brief: `None` does not fall through to ASK

The brief assumed "judge returns `None` so it falls through to ASK". In omnigent 0.17.0 it does not:

* `omnigent/policies/function.py` `_coerce_to_policy_result`: `None` is "treated as ALLOW".
* `omnigent/runtime/policies/engine.py` `PolicyEngine.evaluate`: DENY short-circuits, ASK accumulates, ALLOW
  **continues** to the next policy; if nothing asked, the result is ALLOW. There is no "first decision wins".
* The overview page says the same: all `None` means the action proceeds.

So three separate policies (deny, allow, judge) would let every unmatched command through. `make_gate` runs the
same three stages in one policy and turns "nobody approved" into an explicit ASK. `allow_policy` and the judge keep
the requested `None`-when-unsure contract (and are tested that way) but are not in `POLICY_REGISTRY`.

## Cost cap and call limit

Both live in the judge, per conversation, in a small **ledger file** (`ledger_path`, default
`~/.local/state/tigerhub-omnigent/judge-ledger.json`), written under a file lock and fsync'd.

* **Call limit** `max_judge_calls` (default 20). The count is incremented and persisted *before* the judge is
  called, and counts ALLOW, UNSURE, errors and timeouts alike. Why a file and not only `session_state`: the engine
  withholds a policy's `state_updates` when the result is ASK, so a judge call that ends in UNSURE could never be
  recorded there. The count is still mirrored to `session_state` (`_tigerhub_judge_calls`) on ALLOW and read back
  as a floor. If the ledger cannot be read or written, the judge is skipped (fail closed, so the gate ASKs).
* **Cost cap** `judge_cost_cap_usd` (default 0.50). `max_call_cost_usd` (default 0.02, worst case for one call) is
  reserved before the call; if recorded spend + reservation > cap the judge is not called and the gate ASKs.
  Afterwards the reservation is replaced by the actual cost from `response.usage` token counts and
  `input_usd_per_mtok` / `output_usd_per_mtok`; with no rates or no usage the reservation stays (never under-recorded).
* Session-wide, use omnigent's builtins (`omnigent.policies.builtins.cost.cost_budget`,
  `omnigent.policies.builtins.safety.max_tool_calls_per_session`); not wired up here.

Judge pre-filter (no LLM call at all): command over 1000 chars; any `$`, backtick, backslash, `<(`; wording like
"ignore previous", "verdict", "reply ALLOW"; shells, interpreters, wrappers, network tools, `rm`/`mv`/`cp`,
package managers, `git`/`gh`; any absolute or `~` or `..` path (keeps it inside the worktree).

## Limits

Best-effort text analysis, not a sandbox. Not caught: hard links, globs, `~`/`$VAR`/redirect targets and other indirect paths to the credentials file (only name matching and symlink/realpath/samefile on literal path arguments are done), commands assembled at runtime (`$VAR`, `base64 -d | sh`,
`$'\x63...'`; these are never auto-allowed, so they ASK), repo-local git aliases in `.gitconfig`, scripts the agent
writes then runs. Keep the OS-level permission mode as the real backstop.

## Enabling later (not done)

```yaml
# server config.yaml; repo root on PYTHONPATH
policy_modules:
  - tools.omnigent_policy
```
then attach `tools.omnigent_policy.policies.make_gate` (factory, params above) via the session policy API.

## Tests

```
python3 -m unittest discover -s tools/omnigent_policy/tests -t .
```
Standard library only; the LLM is mocked, no network.
