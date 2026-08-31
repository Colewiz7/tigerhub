/// A real turbo-stream decoder.
///
/// Ported from `backend/app/turbo_stream.py`, which itself revisited docs/notes.md
/// section 8 decision 1. That decision said not to write a general decoder, and
/// it was right for what it covered: occupancy needs four fields out of one
/// known object, so a targeted extractor was less code. The campus map's
/// category data is a nested graph rather than a flat object, and string
/// scanning was tried on it and does not work, so that one needs a real decoder.
///
/// Format, for the next person:
///
/// Everything is one JSON array. Index 0 is the root, and every value is an
/// index into that array rather than an inline value. Objects are written with
/// their keys as `"_<index>"`, so `{"_3": 4}` means "the key at index 3, with
/// the value at index 4". Arrays are lists of indices. Negative indices are
/// sentinels, and a two element list beginning with a type marker is a typed
/// value.
///
/// The graph can contain cycles, so decoding memoises by index and returns a
/// placeholder when it re-enters one.
library;

import 'dart:convert';

// Sentinels, from the turbo-stream reference implementation.
const int _undefined = -1;
const int _null = -2;
const int _nan = -3;
const int _infinity = -4;
const int _negInfinity = -5;
const int _negZero = -6;

// Typed value markers, as the first element of a two element list.
const String _date = 'D';
const String _set = 'S';
const String _map = 'M';
const String _bigint = 'n';
const String _regexp = 'R';
const String _symbol = 'Y';
const String _preserve = 'P';
const String _error = 'E';
const String _nullObj = 'N';

const Map<int, Object?> _scalarSentinels = {
  _undefined: null,
  _null: null,
  _nan: double.nan,
  _infinity: double.infinity,
  _negInfinity: double.negativeInfinity,
  _negZero: -0.0,
};

class TurboStreamError implements Exception {
  TurboStreamError(this.message);
  final String message;
  @override
  String toString() => 'TurboStreamError: $message';
}

/// Decode the first line of a turbo-stream response into plain Dart values.
Object? decodeTurboStream(String raw) {
  final line = raw.split('\n').first.trim();
  if (line.isEmpty) throw TurboStreamError('empty payload');

  Object? flat;
  try {
    flat = jsonDecode(line);
  } on FormatException catch (e) {
    throw TurboStreamError('first line is not JSON: ${e.message}');
  }
  if (flat is! List || flat.isEmpty) {
    throw TurboStreamError('payload is not a non-empty array');
  }

  return _Decoder(flat).resolve(0);
}

class _Decoder {
  _Decoder(this._flat);

  final List<dynamic> _flat;
  final Map<int, Object?> _memo = {};

  /// Indices currently being resolved, so a cycle is detected rather than
  /// blowing the stack.
  final Set<int> _active = {};

  Object? resolve(Object? index) {
    if (index is! int) return index;
    if (_scalarSentinels.containsKey(index)) return _scalarSentinels[index];
    if (index < 0 || index >= _flat.length) return null;
    if (_memo.containsKey(index)) return _memo[index];
    if (_active.contains(index)) {
      // A cycle. Returning null keeps the rest of the graph usable.
      return null;
    }

    _active.add(index);
    Object? value;
    try {
      value = _build(_flat[index], index);
    } finally {
      _active.remove(index);
    }

    _memo[index] = value;
    return value;
  }

  Object? _build(Object? value, int index) {
    if (value is Map) return _object(value, index);
    if (value is List) return _list(value);
    return value;
  }

  Map<String, dynamic> _object(Map<dynamic, dynamic> value, int index) {
    // Memoise the shell first so a self reference finds it.
    final out = <String, dynamic>{};
    _memo[index] = out;
    value.forEach((rawKey, rawValue) {
      final key = _key('$rawKey');
      if (key == null) return;
      out[key] = resolve(rawValue);
    });
    return out;
  }

  String? _key(String rawKey) {
    if (!rawKey.startsWith('_')) return rawKey.isEmpty ? null : rawKey;
    final digits = rawKey.substring(1);
    final parsed = int.tryParse(digits);
    if (parsed == null) return rawKey;
    final resolved = resolve(parsed);
    return resolved is String ? resolved : null;
  }

  Object? _list(List<dynamic> value) {
    // A typed value is a marker string followed by its payload index.
    if (value.length == 2 && value[0] is String && (value[0] as String).length <= 2) {
      final marker = value[0] as String;
      final payload = value[1];
      switch (marker) {
        case _date:
        case _bigint:
        case _regexp:
        case _symbol:
        case _preserve:
        case _error:
          return resolve(payload);
        case _set:
          final items = resolve(payload);
          return items is List ? List<dynamic>.from(items) : items;
        case _map:
          final items = resolve(payload);
          if (items is List) {
            final out = <String, dynamic>{};
            for (var i = 0; i + 1 < items.length; i += 2) {
              out['${items[i]}'] = items[i + 1];
            }
            return out;
          }
          return items;
        case _nullObj:
          return null;
      }
    }
    return [for (final item in value) resolve(item)];
  }
}

/// Every value stored under [key], at any depth.
///
/// Decoded map payloads nest categories inside categories, so the useful lists
/// are easier to collect by key than by walking a known path that RIT may
/// change.
List<Object?> findAll(Object? node, String key) {
  final found = <Object?>[];
  final seen = <Object>{};

  void walk(Object? value) {
    if (value is Map || value is List) {
      if (!seen.add(value!)) return;
    }
    if (value is Map) {
      value.forEach((k, v) {
        if (k == key) found.add(v);
        walk(v);
      });
    } else if (value is List) {
      for (final item in value) {
        walk(item);
      }
    }
  }

  walk(node);
  return found;
}
