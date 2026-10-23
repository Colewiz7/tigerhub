/// Host side of ios_screens_test, writes each screenshot as a png
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  // skips the big json dump of the run
  responseDataCallback: null,
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/ios_screens/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
