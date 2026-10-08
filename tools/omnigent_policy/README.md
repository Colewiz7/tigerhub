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

Both live in the judge, per conversation, in a **ledger file** (`ledger_path`, default
`~/.local/state/tigerhub-omnigent/judge-ledger.json`; file mode 0600, directory 0700), updated under a file lock
and fsync'd. The judge returns an explicit **ASK** (never DENY) whenever this machinery cannot vouch for a call.

* **Prices are required.** `input_usd_per_mtok` and `output_usd_per_mtok` must be configured (finite, >= 0).
  Without them the judge never runs and the gate ASKs.
* **Worst case per call** = (maximum input tokens + the enforced `max_tokens` on the request) x the prices.
  Input is bounded by `judge_input_bound` (one token per UTF-8 byte of instructions + command + schema, plus 256 slack;
  commands are capped at 1000 chars). Output is bounded by `judge_max_tokens` (default 100), sent as `max_tokens`
  (omnigent's documented kwarg). This worst case is reserved before the call; if recorded + reservation >
  `judge_cost_cap_usd` (default 0.50) the call is refused and the gate ASKs.
* **After the call** the reservation is replaced by the actual cost from `response.usage`. Unknown usage keeps the
  FULL reservation. Usage above the bounds (a provider ignoring `max_tokens`) is recorded as reported, taints the
  ledger and ASKs. So a call at the maximum cannot push spend over the cap; the cap can only be exceeded by a
  provider that disobeys `max_tokens`, and then every later call ASKs.
* **Call limit** `max_judge_calls` (default 20). Incremented and persisted *before* the call; ALLOW, UNSURE, errors
  and timeouts all count. A file rather than only `session_state` because the engine withholds `state_updates` on
  ASK; the count is still mirrored to `session_state` (`_tigerhub_judge_calls`) on ALLOW and read back as a floor.
* **Ledger failures and taint.** If writing the actual cost back fails after a call, the result is ASK (even if the
  judge said ALLOW) and the ledger is tainted. Taint is kept in up to three places and ANY ONE forces ASK on every
  call, including from a fresh process after a restart: (1) in memory; (2) a `_tainted` mark in the ledger, written
  under the same flock as reserve/settle; (3) if (2) cannot be written, a separate `<ledger>.tainted` sentinel file,
  created O_EXCL, mode 0600, fsync'd along with its directory. Before every judge call the ledger is rewritten under
  the lock (so it must be writable) and both markers are checked first. If even the sentinel cannot be created, only
  (1) remains and a restart loses it; that residual risk is unavoidable without a working disk. To reset after a
  taint, delete the ledger's `_tainted` mark and the `.tainted` file by hand.
  The ledger is parsed with NaN/Infinity rejected and every record validated (types, finite, non-negative, exact
  fields); anything invalid is treated as corrupt and ASKs.
* **`cd`/`pushd`/`popd`** anywhere in a command (chains, `bash -c`, wrappers) => ASK, judge not consulted.
* Session-wide, use omnigent's builtins (`omnigent.policies.builtins.cost.cost_budget`,
  `omnigent.policies.builtins.safety.max_tool_calls_per_session`); not wired up here.

Judge pre-filter (no LLM call at all): `cd`/`pushd`/`popd`; command over 1000 chars; any `$`, backtick, backslash, `<(`; wording like
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
