/// Scheme source for platforms with no filesystem, which is Web.
///
/// Web gets the fixed seed fallback. There is no wallpaper to follow and no
/// file to read, so this reports nothing and the app builds from the seed.
library;

Future<Map<String, dynamic>?> readScheme() async => null;

Stream<Map<String, dynamic>> watchScheme() => const Stream.empty();

String get schemeSourceDescription => 'fixed seed (web has no scheme file)';
