/// Open menu of every surface at the review sizes, light and dark, text 1.0 and 2.0.
///
/// Set CONTEXT_MENU_SHOTS to a directory to write the PNGs there. Without it
/// the matrix still runs and fails on overflow or a menu that leaves the screen.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/rit_clock.dart';

import 'golden_harness.dart';
import 'support/context_menu_harness.dart';
import 'support/context_menu_surfaces.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final outDir = Platform.environment['CONTEXT_MENU_SHOTS'];

  setUpAll(() {
    if (outDir != null) Directory(outDir).createSync(recursive: true);
  });
  setUp(prepareMenuEnvironment);
  tearDown(RitClock.reset);

  const sizes = [Size(390, 844), Size(430, 932)];

  for (final surface in menuSurfaces) {
    for (final size in sizes) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final name = '${surface.name.replaceAll(' ', '_')}_${size.width.toInt()}x${size.height.toInt()}_${dark ? 'dark' : 'light'}_${scale.toInt()}x';
          goldenWidgets(name, (tester) async {
            MenuProbe().install(tester);
            final key = GlobalKey();
            await pumpSurface(tester, surface, size: size, dark: dark, textScale: scale, boundaryKey: key);
            await longPress(tester, surface.target());
            await expectMenuOpen(tester, surface.labels);

            final screen = Offset.zero & size;
            final menu = tester.getRect(find.ancestor(of: menuItems.first, matching: find.byType(Material)).first);
            expect(screen.contains(menu.topLeft) && screen.contains(menu.bottomRight), isTrue, reason: 'menu $menu leaves the screen $screen');
            expect(tester.takeException(), isNull);

            if (outDir == null) return;
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
              final image = await boundary.toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
            });
          });
        }
      }
    }
  }
}
