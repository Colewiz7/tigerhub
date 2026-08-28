/// Platform-conditional access to the generated scheme file.
library;

export 'scheme_source_stub.dart' if (dart.library.io) 'scheme_source_io.dart';
