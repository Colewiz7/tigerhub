/// File backed JSON storage.
///
/// Offline first is a hard requirement (docs/notes.md 3.1), and going client side
/// made the payloads the app holds considerably larger: events alone is about
/// 232 KB, where the old comment in `services/cache.dart` still assumed 24 KB.
/// That is past what shared_preferences should be asked to carry, since Android
/// reads the entire preference map into memory at launch, so snapshots live in
/// real files and preferences go back to holding only small settings.
///
///   Linux    ~/.local/share/dev.colewiz.tigerhub/
///   Android  /data/data/dev.colewiz.tigerhub/files/
///
/// Writes go to a temp file and then rename, so a crash or a pulled battery
/// mid-write leaves the previous good snapshot in place rather than a truncated
/// one. A half written cache is worse than a stale cache.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class StoredJson {
  const StoredJson({required this.body, required this.fetchedAt});

  final Map<String, dynamic> body;
  final DateTime fetchedAt;
}

class JsonStore {
  JsonStore._(this._dir);

  final Directory _dir;

  static JsonStore? _instance;

  static Future<JsonStore> open() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _instance = JsonStore._(dir);
  }

  /// For tests, which should not touch the real application support directory.
  static JsonStore overrideForTesting(Directory dir) =>
      _instance = JsonStore._(dir);

  /// The store [overrideForTesting] installed, for injecting directly.
  static JsonStore get overrideForTestingInstance =>
      _instance ?? (throw StateError('JsonStore.overrideForTesting() has not run'));

  /// `/dining/23/occupancy?x=1` becomes `dining-23-occupancy-x-1`, so a key is
  /// always a single safe filename regardless of what path produced it.
  static String fileNameFor(String key) {
    final safe = key
        .replaceAll(RegExp(r'^/+'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${safe.isEmpty ? 'root' : safe}.json';
  }

  File _fileFor(String key) => File('${_dir.path}/${fileNameFor(key)}');

  Future<void> write(
    String key,
    Map<String, dynamic> body, {
    String? fingerprint,
  }) async {
    final envelope = jsonEncode({
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
      'fingerprint': ?fingerprint,
      'body': body,
    });

    final target = _fileFor(key);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(envelope, flush: true);
    await temp.rename(target.path);
  }

  Future<StoredJson?> read(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final body = decoded['body'];
      if (body is! Map<String, dynamic>) return null;
      return StoredJson(
        body: body,
        fetchedAt:
            DateTime.tryParse(decoded['fetched_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
    } catch (_) {
      // A corrupt snapshot is not worth crashing over. Treat it as a miss and
      // let the next refresh replace it.
      return null;
    }
  }

  /// What the source's inputs looked like when [key] was written.
  ///
  /// A snapshot is only comparable to what the app would fetch today if it was
  /// built from the same request set. Registering a new map category changed
  /// what a scrape returns without changing its schedule, so a 12 hour cadence
  /// meant the new places did not appear until the next day.
  Future<String?> fingerprintOf(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return decoded['fingerprint'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// When [key] was last written, without paying to decode the payload. Used by
  /// the refresh cadence to decide whether a source is due.
  Future<DateTime?> fetchedAt(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    try {
      return (await file.lastModified()).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String key) async {
    final file = _fileFor(key);
    if (await file.exists()) await file.delete();
  }
}
