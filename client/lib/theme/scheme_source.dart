/// Access to the generated scheme file.
///
/// This used to be a platform-conditional export, because the web target had no
/// filesystem and needed a stub. Web was dropped, and both remaining targets
/// (Linux and Android) have dart:io, so the conditional and its stub are gone.
///
/// The io implementation is safe on Android by construction: it looks for
/// Caelestia's scheme file under HOME, finds nothing, and reports nothing, so
/// the app builds from the shipped seed.
library;

export 'scheme_source_io.dart';
