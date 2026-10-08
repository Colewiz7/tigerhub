"""Shell command analysis used by the TigerHub Omnigent policies.

Pure functions, standard library only. Everything here is deliberately
conservative: when a command cannot be understood the callers fall back to
"do not auto-allow" (and, for the deny list, to a plain-text scan).
"""

from __future__ import annotations

import os
import re
import shlex
from collections.abc import Iterator

MAX_DEPTH = 5
MAX_TOKENS = 500

_OPERATOR_CHARS = frozenset("();<>|&")

# Wrappers that run another command given in their trailing arguments. For
# these every suffix of the argv is treated as a candidate command, so flags
# and flag values (`env -u X git push`, `timeout -s KILL 5 git push`) cannot
# push the real command out of sight.
WRAPPERS = frozenset(
    {
        "sudo", "doas", "pkexec", "env", "nohup", "timeout", "nice", "ionice",
        "time", "command", "builtin", "exec", "setsid", "stdbuf", "xargs",
        "find", "watch", "parallel", "flock", "busybox", "strace", "su",
        "script", "unbuffer", "chroot", "ssh", "eval",
    }
)
PRIVILEGE_ESCALATORS = frozenset({"sudo", "doas", "pkexec"})
SHELLS = frozenset({"sh", "bash", "zsh", "dash", "ksh", "fish"})
SCRIPT_INTERPRETERS = re.compile(
    r"^(python[\d.]*|perl|ruby|node|nodejs|php|lua|awk|gawk|deno|bun)$"
)
_C_FLAG = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# Credentials file. Matched on the command text with quotes and backslashes
# removed, so `codemagic_"api".txt` and `code\magic_api` still hit.
_CREDS_PATTERNS = (
    re.compile(r"codemagic_api"),
    re.compile(r"codemagic[_\W]*[a*?\[]"),  # codemagic_a*, codemagic*, codemagic_?pi
    re.compile(r"[*?\[][^\s/]*_api\.?t?x?t?(?:\s|$)"),  # *_api.txt style globs
)

# Last-resort text scan, used only when a command cannot be tokenised or for
# the code argument of script interpreters (`python -c ...`).
_SMELLS = re.compile(
    r"\bsudo\b|\bdoas\b"
    r"|\bgit\b\W+(?:[\w.=/-]+\W+){0,6}?push\b"
    r"|\bgh\b\W+(?:[\w.=/-]+\W+){0,4}?pr\W+(?:[\w.=/-]+\W+){0,3}?(?:merge|create|close)\b"
    r"|\brm\b\W+(?:[\w=/.-]*\W+){0,3}?-{1,2}[a-zA-Z-]*[rRfF]",
    re.IGNORECASE,
)


class Unparseable(Exception):
    """The command could not be broken into simple commands safely."""


# ── credentials ──────────────────────────────────────────────────────────────


def normalize_for_creds(text: str) -> str:
    """Lower-case *text* with quote and backslash characters removed."""
    return re.sub(r"['\"\\]", "", text).lower()


def mentions_credentials(text: str) -> bool:
    """True if *text* names (or globs towards) a ``*codemagic_api*`` file."""
    norm = normalize_for_creds(text)
    return any(p.search(norm) for p in _CREDS_PATTERNS)


# ── tokenising ───────────────────────────────────────────────────────────────


def _substitution_bodies(text: str) -> list[str]:
    """Bodies of ``$(..)``, ``<(..)``, ``>(..)`` and backtick substitutions."""
    bodies: list[str] = []
    i = 0
    while i < len(text) - 1:
        if text[i] in "$<>" and text[i + 1] == "(":
            depth, j = 1, i + 2
            while j < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            bodies.append(text[i + 2 : j - 1 if depth == 0 else j])
            i += 2
        else:
            i += 1
    parts = text.split("`")
    bodies.extend(parts[1::2])
    return bodies


def _split_segments(text: str) -> list[list[str]]:
    lex = shlex.shlex(text.replace("\r", "\n").replace("\n", " ; "), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        tokens = list(lex)
    except ValueError as exc:  # unbalanced quote, dangling escape
        raise Unparseable(str(exc)) from exc
    if len(tokens) > MAX_TOKENS:
        raise Unparseable("too many tokens")
    segments: list[list[str]] = [[]]
    for tok in tokens:
        if tok and set(tok) <= _OPERATOR_CHARS:
            segments.append([])
        else:
            segments[-1].append(tok)
    return [s for s in segments if s]


def _strip_assignments(argv: list[str]) -> list[str]:
    i = 0
    while i < len(argv) and _ASSIGNMENT.match(argv[i]):
        i += 1
    return argv[i:]


def head_name(argv: list[str]) -> str:
    """Basename of argv[0] (``/usr/bin/git`` -> ``git``)."""
    return os.path.basename(argv[0]) if argv else ""


def simple_commands(command: str, _depth: int = 0) -> Iterator[list[str]]:
    """Yield the argv of every simple command in *command*.

    Looks through chaining (``; && || | &``, newlines), env-assignment
    prefixes, quoting, ``$(..)``/backtick substitutions, wrappers
    (``sudo``, ``env``, ``timeout`` ...) and ``bash -c`` / ``eval`` strings.
    Raises :class:`Unparseable` when it cannot.
    """
    if _depth > MAX_DEPTH:
        raise Unparseable("nesting too deep")
    for body in _substitution_bodies(command):
        yield from simple_commands(body, _depth + 1)
    for segment in _split_segments(command):
        yield from _unwrap(segment, _depth)


def _unwrap(argv: list[str], depth: int) -> Iterator[list[str]]:
    argv = _strip_assignments(argv)
    if not argv:
        return
    yield argv
    head = head_name(argv)
    if head in SHELLS:
        for i, arg in enumerate(argv[1:], start=1):
            if _C_FLAG.match(arg) and i + 1 < len(argv):
                yield from simple_commands(argv[i + 1], depth + 1)
                break
    if head in WRAPPERS:
        for i in range(1, len(argv)):
            yield from _unwrap(argv[i:], depth + 1) if depth < MAX_DEPTH else iter(())
        for arg in argv[1:]:
            if any(c.isspace() for c in arg):  # `env -S "git push"`, `watch "..."`
                yield from simple_commands(arg, depth + 1)


# ── deny classification ──────────────────────────────────────────────────────


def _rm_recursive_force(args: list[str]) -> bool:
    recursive = force = False
    for arg in args:
        if arg == "--":
            break
        if arg.startswith("--"):
            if len(arg) >= 3 and "--recursive".startswith(arg):
                recursive = True
            if len(arg) >= 3 and "--force".startswith(arg):
                force = True
            if arg == "--no-preserve-root":
                return True
        elif arg.startswith("-") and len(arg) > 1:
            recursive = recursive or any(c in "rR" for c in arg[1:])
            force = force or "f" in arg[1:]
    return recursive and force


_GIT_VALUE_OPTS = frozenset(
    {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"}
)


def git_subcommand(args: list[str]) -> tuple[str | None, list[str], bool]:
    """(subcommand, its args, alias_override_seen) for git's argv[1:]."""
    alias = False
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in _GIT_VALUE_OPTS:
            if arg in ("-c", "--config-env") and i + 1 < len(args):
                alias = alias or args[i + 1].lower().startswith("alias.")
            i += 2
        elif arg.startswith("-"):
            alias = alias or arg.lower().startswith("-calias.")
            i += 1
        else:
            return arg, args[i + 1 :], alias
    return None, [], alias


def gh_positionals(args: list[str]) -> list[str]:
    """Non-flag arguments of gh, skipping the value of -R/--repo."""
    out: list[str] = []
    i = 0
    while i < len(args):
        if args[i] in ("-R", "--repo", "--hostname"):
            i += 2
        elif args[i].startswith("-"):
            i += 1
        else:
            out.append(args[i])
            i += 1
    return out


def deny_reason_for_argv(argv: list[str]) -> str | None:
    head = head_name(argv)
    args = argv[1:]
    if head in PRIVILEGE_ESCALATORS:
        return f"`{head}` is not permitted"
    if head == "rm" and _rm_recursive_force(args):
        return "recursive forced `rm` is not permitted"
    if head == "git":
        sub, _, alias = git_subcommand(args)
        if alias:
            return "overriding git aliases with -c alias.* is not permitted"
        if sub == "push":
            return "`git push` is not permitted"
    if head == "gh":
        pos = gh_positionals(args)
        if len(pos) >= 2 and pos[0] == "pr" and pos[1] in ("merge", "create", "close"):
            return f"`gh pr {pos[1]}` is not permitted"
    if SCRIPT_INTERPRETERS.match(head):
        for arg in args:
            if _SMELLS.search(arg):
                return "script interpreter code contains a denied operation"
    return None


def deny_reason(command: str) -> str | None:
    """Why *command* must be blocked outright, or None if nothing matched."""
    if mentions_credentials(command):
        return "touches the Codemagic credentials file"
    try:
        for argv in simple_commands(command):
            reason = deny_reason_for_argv(argv)
            if reason:
                return reason
    except Unparseable:
        if _SMELLS.search(command):
            return "unparseable command containing a denied operation"
    return None
