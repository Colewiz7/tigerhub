/// Scheme source for Linux desktop.
///
/// Caelestia regenerates a Material scheme from the wallpaper and writes it to
/// a JSON file. Reading that file is what makes the app follow the wallpaper
/// rather than merely looking as though it does.
///
/// Path verified on this machine 2026-08-28. Note that the matugen config also
/// names ~/.local/state/quickshell/user/generated/colors.json, an end-4
/// illogical-impulse target, but that file does not exist here. Caelestia is
/// what actually runs, so its own state file is the live one. Both are checked
/// at runtime, most likely first.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Candidate scheme files, most likely first.
List<String> _candidates() {
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return const [];
  return [
    '$home/.local/state/caelestia/scheme.json',
    '$home/.local/state/quickshell/user/generated/colors.json',
  ];
}

File? _locate() {
  for (final path in _candidates()) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

Future<Map<String, dynamic>?> readScheme() async {
  final file = _locate();
  if (file == null) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    // A half written file during a wallpaper change is expected. Keep the
    // scheme already in use rather than falling back to the seed and flashing.
    return null;
  }
}

/// Emits whenever the scheme file changes on disk.
///
/// The directory is watched rather than the file, because the writer replaces
/// the file rather than editing it in place, which would break a file watch.
Stream<Map<String, dynamic>> watchScheme() async* {
  final file = _locate();
  if (file == null) return;

  final directory = file.parent;
  if (!directory.existsSync()) return;

  await for (final event in directory.watch()) {
    if (!event.path.endsWith(file.uri.pathSegments.last)) continue;
    // Small settle delay so a rewrite is complete before it is parsed.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final scheme = await readScheme();
    if (scheme != null) yield scheme;
  }
}

String get schemeSourceDescription =>
    _locate()?.path ?? 'fixed seed (no scheme file found)';
