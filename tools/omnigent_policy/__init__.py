"""TigerHub custom Omnigent policy module. Not enabled anywhere; see README.md.

Server config would list it as ``policy_modules: [tools.omnigent_policy]``
(with the repo root on PYTHONPATH). omnigent scans this module's
``POLICY_REGISTRY`` list (omnigent.policies.registry.load_registry).
"""

from __future__ import annotations

POLICY_REGISTRY: list[dict[str, object]] = [
    {
        "handler": "tools.omnigent_policy.policies.deny_policy",
        "kind": "callable",
        "name": "TigerHub Shell Deny List",
        "description": (
            "DENY: Codemagic credentials file, sudo, rm -rf, git push, "
            "gh pr merge/create/close (robust to chaining, quoting, wrappers, bash -c)."
        ),
    },
    {
        "handler": "tools.omnigent_policy.policies.make_gate",
        "kind": "factory",
        "name": "TigerHub Shell Gate",
        "description": (
            "Deny list, then allow list (flutter/dart/read-only git+gh), then an "
            "LLM judge that can only ALLOW, then an explicit ASK. Judge has a call "
            "limit and a session cost cap."
        ),
        "params_schema": {
            "type": "object",
            "properties": {
                "max_judge_calls": {"type": "integer", "default": 20, "minimum": 0,
                                    "description": "Hard limit on judge LLM calls per conversation"},
                "judge_cost_cap_usd": {"type": "number", "default": 0.5, "minimum": 0,
                                       "description": "Cap on cumulative judge spend per conversation (USD)"},
                "max_call_cost_usd": {"type": "number", "default": 0.02, "minimum": 0,
                                      "description": "Worst-case cost of one judge call, reserved before the call"},
                "ledger_path": {"type": "string",
                                "description": "JSON file holding judge call counts and spend (survives restarts)"},
                "input_usd_per_mtok": {"type": "number", "description": "Judge model input price, to record actual cost"},
                "output_usd_per_mtok": {"type": "number", "description": "Judge model output price, to record actual cost"},
                "credentials_path": {"type": "string", "description": "Credentials file to protect (symlinks resolved)"},
                "judge_timeout_s": {"type": "number", "default": 20, "exclusiveMinimum": 0,
                                    "description": "Judge call timeout in seconds"},
            },
        },
    },
]
