/// Glass belongs to the navigation layer only. The iOS tab bar is the one
/// place that blurs; cards, rows and Today's header stay solid.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowed = {'lib/widgets/tab_bar.dart'};

void main() {
  test('no blur outside the tab bar', () {
    final blur = RegExp(r'BackdropFilter|ImageFilter\.blur');
    final found = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && blur.hasMatch(file.readAsStringSync())) file.path.replaceAll(r'\', '/'),
    ];
    expect(found.where((path) => !_allowed.contains(path)), isEmpty);
    // the allowed one still exists, so the list cannot go stale
    for (final path in _allowed) {
      expect(found, contains(path));
    }
  });
}
