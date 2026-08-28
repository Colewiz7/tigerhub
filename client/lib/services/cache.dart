/// Local response cache.
///
/// Offline first is a hard requirement (CLAUDE.md 3.1), so every API response
/// is persisted verbatim and replayed on the next launch. Payloads are small,
/// the largest being dining at roughly 24 KB, so shared_preferences holding
/// JSON strings is enough and avoids pulling in a database.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedResponse {
  const CachedResponse({required this.body, required this.fetchedAt});

  final Map<String, dynamic> body;
  final DateTime fetchedAt;
}

class ResponseCache {
  ResponseCache._(this._prefs);

  final SharedPreferencesAsync _prefs;

  static ResponseCache? _instance;

  /// SharedPreferences.getInstance() is the legacy API and is on its way out,
  /// so this uses SharedPreferencesAsync.
  static ResponseCache get instance =>
      _instance ??= ResponseCache._(SharedPreferencesAsync());

  static String _key(String path) => 'cache:$path';
  static String _stampKey(String path) => 'cache_at:$path';

  Future<void> write(String path, Map<String, dynamic> body) async {
    await _prefs.setString(_key(path), jsonEncode(body));
    await _prefs.setString(
      _stampKey(path),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<CachedResponse?> read(String path) async {
    final raw = await _prefs.getString(_key(path));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final stamp = await _prefs.getString(_stampKey(path));
      return CachedResponse(
        body: decoded,
        fetchedAt: DateTime.tryParse(stamp ?? '')?.toLocal() ?? DateTime.now(),
      );
    } catch (_) {
      // A corrupt entry is not worth crashing over. Treat it as a cache miss.
      return null;
    }
  }

  Future<List<String>> readOrder(String key) async =>
      await _prefs.getStringList('order:$key') ?? const [];

  Future<void> writeOrder(String key, List<String> order) =>
      _prefs.setStringList('order:$key', order);
}
