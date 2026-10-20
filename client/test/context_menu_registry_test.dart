/// One loop over every context menu surface, so a new menu cannot ship untested.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/services/preferences.dart';
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
      // ids follow the order labels were first seen in the process, not the menu
      expect([for (final id in ids) CustomSemanticsAction.getAction(id)!.label], unorderedEquals(surface.labels));
      handle.dispose();
    });
  }

  testWidgets('mute hides the row and the snackbar undo brings it back', (tester) async {
    final probe = MenuProbe()..install(tester);
    final surface = menuSurfaces.firstWhere((s) => s.name == 'event row');
    final row = surface.build();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: menuTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Preferences.instance,
            builder: (context, _) => Preferences.instance.mutedOrganizers.contains('student-life') ? const SizedBox() : row,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await secondaryTap(tester, surface.target());
    await tapMenuItem(tester, 'Mute organizer');
    expect(surface.target(), findsNothing);
    expect(Preferences.instance.mutedOrganizers, contains('student-life'));
    expect(find.text('Muted Student Life'), findsOneWidget);
    expect(probe.announcements, ['Muted Student Life']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(Preferences.instance.mutedOrganizers, isEmpty);
    expect(surface.target(), findsOneWidget);
  });

  testWidgets('the mute snackbar dismisses itself', (tester) async {
    MenuProbe().install(tester);
    final surface = menuSurfaces.firstWhere((s) => s.name == 'event row');
    await pumpSurface(tester, surface);
    await secondaryTap(tester, surface.target());
    await tapMenuItem(tester, 'Mute organizer');
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a failed menu launch copies through the shared feedback', (tester) async {
    final probe = MenuProbe()..install(tester);
    probe.launcherWorks = false;
    final surface = menuSurfaces.firstWhere((s) => s.name == 'event row');
    await pumpSurface(tester, surface);
    await secondaryTap(tester, surface.target());
    await tapMenuItem(tester, 'Open page');
    expect(probe.clipboard, ['https://example.edu/events/open-mic']);
    expect(find.text('Event link copied'), findsOneWidget);
    expect(probe.announcements, ['Event link copied']);
  });

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
