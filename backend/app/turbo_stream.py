"""A real turbo-stream decoder.

**This revisits CLAUDE.md section 8 decision 1**, which said not to write one.
That decision was right for what it covered: occupancy needed four fields out of
one known object, and a targeted extractor was less code and less to maintain
than a general decoder. `scrapers/maps_occupancy.py` still uses that extractor
and is deliberately left alone.

The requirement has since changed. The campus map's category data is a nested
graph, not a flat object: categories contain sub-categories contain locations,
each with coordinates, a building, a floor and a description. Reaching that with
string scanning was tried and does not work, so the graph has to be decoded
properly.

Format, for the next person:

Everything is one JSON array. Index 0 is the root, and every value is an index
into that array rather than an inline value. Objects are written with their keys
as `"_<index>"`, so `{"_3": 4}` means "the key at index 3, with the value at
index 4". Arrays are lists of indices. Negative indices are sentinels, and a
two-element list beginning with a type marker is a typed value.

The graph can contain cycles, so decoding memoises by index and returns a
placeholder when it re-enters one.
"""

from __future__ import annotations

import json
from typing import Any

# Sentinels, from the turbo-stream reference implementation.
_UNDEFINED = -1
_NULL = -2
_NAN = -3
_INFINITY = -4
_NEG_INFINITY = -5
_NEG_ZERO = -6

# Typed value markers, as the first element of a two element list.
_DATE = "D"
_SET = "S"
_MAP = "M"
_BIGINT = "n"
_REGEXP = "R"
_SYMBOL = "Y"
_PRESERVE = "P"
_ERROR = "E"
_NULL_OBJ = "N"

_SCALAR_SENTINELS = {
    _UNDEFINED: None,
    _NULL: None,
    _NAN: float("nan"),
    _INFINITY: float("inf"),
    _NEG_INFINITY: float("-inf"),
    _NEG_ZERO: -0.0,
}


class TurboStreamError(ValueError):
    """The payload was not decodable turbo-stream."""


def decode(raw: str) -> Any:
    """Decode the first line of a turbo-stream response into plain Python."""
    line = raw.split("\n", 1)[0].strip()
    if not line:
        raise TurboStreamError("empty payload")
    try:
        flat = json.loads(line)
    except json.JSONDecodeError as exc:
        raise TurboStreamError(f"first line is not JSON: {exc}") from exc
    if not isinstance(flat, list) or not flat:
        raise TurboStreamError("payload is not a non-empty array")

    return _Decoder(flat).resolve(0)


class _Decoder:
    def __init__(self, flat: list) -> None:
        self._flat = flat
        self._memo: dict[int, Any] = {}
        # Indices currently being resolved, so a cycle can be detected rather
        # than blowing the stack.
        self._active: set[int] = set()

    def resolve(self, index: Any) -> Any:
        if not isinstance(index, int):
            return index
        if index in _SCALAR_SENTINELS:
            return _SCALAR_SENTINELS[index]
        if index < 0 or index >= len(self._flat):
            return None
        if index in self._memo:
            return self._memo[index]
        if index in self._active:
            # A cycle. Returning None keeps the rest of the graph usable.
            return None

        self._active.add(index)
        try:
            value = self._build(self._flat[index], index)
        finally:
            self._active.discard(index)

        self._memo[index] = value
        return value

    def _build(self, value: Any, index: int) -> Any:
        if isinstance(value, dict):
            return self._object(value, index)
        if isinstance(value, list):
            return self._list(value)
        return value

    def _object(self, value: dict, index: int) -> dict:
        # Memoise the shell first so a self reference finds it.
        out: dict[str, Any] = {}
        self._memo[index] = out
        for raw_key, raw_value in value.items():
            key = self._key(raw_key)
            if key is None:
                continue
            out[key] = self.resolve(raw_value)
        return out

    def _key(self, raw_key: str) -> str | None:
        if not raw_key.startswith("_"):
            return raw_key or None
        digits = raw_key[1:]
        if not digits.lstrip("-").isdigit():
            return raw_key
        resolved = self.resolve(int(digits))
        return resolved if isinstance(resolved, str) else None

    def _list(self, value: list) -> Any:
        # A typed value is a marker string followed by its payload index.
        if len(value) == 2 and isinstance(value[0], str) and len(value[0]) <= 2:
            marker, payload = value
            if marker == _DATE:
                return self.resolve(payload)
            if marker in (_BIGINT, _REGEXP, _SYMBOL, _PRESERVE, _ERROR):
                return self.resolve(payload)
            if marker == _SET:
                items = self.resolve(payload)
                return list(items) if isinstance(items, list) else items
            if marker == _MAP:
                items = self.resolve(payload)
                if isinstance(items, list):
                    pairs = zip(items[0::2], items[1::2])
                    return {str(k): v for k, v in pairs}
                return items
            if marker == _NULL_OBJ:
                return None
        return [self.resolve(item) for item in value]


def find_all(node: Any, key: str) -> list[Any]:
    """Every value stored under `key`, at any depth.

    Decoded map payloads nest categories inside categories, so the useful lists
    are easier to collect by key than by walking a known path that RIT may
    change.
    """
    found: list[Any] = []
    seen: set[int] = set()

    def walk(value: Any) -> None:
        if id(value) in seen:
            return
        if isinstance(value, (dict, list)):
            seen.add(id(value))
        if isinstance(value, dict):
            for k, v in value.items():
                if k == key:
                    found.append(v)
                walk(v)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(node)
    return found
