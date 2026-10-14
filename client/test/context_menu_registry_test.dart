/// One loop over every context menu surface, so a new menu cannot ship untested.
library;

import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/widgets/context_actions.dart';

import 'support/context_menu_harness.dart';
import 'support/context_menu_surfaces.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(prepareMenuEnvironment);
  tearDown(RitClock.reset);

  for (final surface in menuSurfaces) {
    testWidgets('${surface.name}: labels, effects, close paths', (tester) async {
      await checkSurface(tester, surface);
    });

    testWidgets('${surface.name}: opens from the keyboard', (tester) async {
      final probe = MenuProbe()..install(tester);
      await pumpSurface(tester, surface);

      await keyboardOpen(tester, surface.target());
      await expectMenuOpen(tester, surface.labels);
      expect(probe.haptics, ['HapticFeedbackType.lightImpact']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await expectMenuClosed(tester);

      await keyboardOpen(tester, surface.target(), shiftF10: true);
      await expectMenuOpen(tester, surface.labels);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await expectMenuClosed(tester);
    });

    testWidgets('${surface.name}: custom semantics actions match the menu', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSurface(tester, surface);

      final row = find.ancestor(of: surface.target(), matching: find.byType(ContextActions)).first;
      final ids = tester.getSemantics(row).getSemanticsData().customSemanticsActionIds!;
      expect([for (final id in ids) CustomSemanticsAction.getAction(id)!.label], surface.labels);
      handle.dispose();
    });
  }

  test('every file that builds menu actions has a registry entry', () {
    final registered = {for (final surface in menuSurfaces) ...surface.files};
    final building = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = file.path;
      if (!path.endsWith('.dart') || path.endsWith('widgets/context_actions.dart')) continue;
      if (file.readAsStringSync().contains(RegExp(r'MenuAction[.(]'))) building.add(path);
    }
    expect(registered, containsAll(building), reason: 'add the new surface to test/support/context_menu_surfaces.dart');
    expect(building, containsAll(registered), reason: 'a registry entry points at a file with no menu');
  });
}
