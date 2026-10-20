"""Copy style scanners for Dart source, used by ci-checks.py."""
import re

OPEN = "([{"
CLOSE = ")]}"
BANNED_ARGS = {"body", "message", "detail"}
CALL = re.compile(r"(?<![\w.])EmptyState(?:\s*\.\s*\w+)?\s*\(")
NAMED_ARG = re.compile(r"^(\w+)\s*:(?!:)")
EM_DASH = "—"


def blank(c):
    return c if c == "\n" else " "


# blanks comments, and string contents unless keep_strings. length and
# newlines are kept so offsets and line numbers still match the source
def strip_dart(text, keep_strings=False):
    out = []
    n = len(text)
    i = 0
    string = None
    pending = []
    while i < n:
        c = text[i]
        if string is None:
            if text.startswith("//", i):
                while i < n and text[i] != "\n":
                    out.append(" ")
                    i += 1
                continue
            if text.startswith("/*", i):
                depth = 0
                while i < n:
                    if text.startswith("/*", i):
                        depth += 1
                        out.append("  ")
                        i += 2
                    elif text.startswith("*/", i):
                        depth -= 1
                        out.append("  ")
                        i += 2
                        if depth == 0:
                            break
                    else:
                        out.append(blank(text[i]))
                        i += 1
                continue
            if c in "'\"":
                raw = i > 0 and text[i - 1] == "r" and (i < 2 or not re.match(r"\w", text[i - 2]))
                quote = c * 3 if text.startswith(c * 3, i) else c
                string = (quote, raw)
                out.append(quote)
                i += len(quote)
                continue
            if pending and c == "{":
                pending[-1][1] += 1
            elif pending and c == "}":
                if pending[-1][1] == 0:
                    string = pending.pop()[0]
                    out.append("}" if keep_strings else " ")
                    i += 1
                    continue
                pending[-1][1] -= 1
            # an interpolation expression is code, so it stays visible
            out.append(c)
            i += 1
            continue
        quote, raw = string
        if c == "\\" and not raw:
            out.append(c + text[i + 1 : i + 2] if keep_strings else "  ")
            i += 2
        elif c == "$" and not raw and text.startswith("{", i + 1):
            pending.append([string, 0])
            string = None
            out.append("${" if keep_strings else "  ")
            i += 2
        elif text.startswith(quote, i):
            out.append(quote)
            string = None
            i += len(quote)
        elif c == "\n" and len(quote) == 1:
            out.append(c)
            string = None
            i += 1
        else:
            out.append(c if keep_strings else blank(c))
            i += 1
    return "".join(out)


# top level named args of one call, given the index just after its open paren
def top_level_arg_names(code, start):
    segments = []
    depth = 1
    segment = []
    i = start
    while i < len(code) and depth > 0:
        c = code[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
        if depth == 1 and c == ",":
            segments.append("".join(segment))
            segment = []
        elif depth > 0:
            segment.append(c)
        i += 1
    segments.append("".join(segment))
    found = []
    for seg in segments:
        m = NAMED_ARG.match(seg.strip())
        if m:
            found.append(m.group(1))
    return found


def empty_state_violations(text):
    code = strip_dart(text)
    hits = []
    for m in CALL.finditer(code):
        before = code[: m.start()].rstrip()
        if before.endswith("class"):
            continue
        line = code.count("\n", 0, m.start()) + 1
        for name in top_level_arg_names(code, m.end()):
            if name in BANNED_ARGS:
                hits.append((line, name))
    return hits


def em_dash_lines(text):
    code = strip_dart(text, keep_strings=True)
    return [n for n, line in enumerate(code.splitlines(), 1) if EM_DASH in line]
