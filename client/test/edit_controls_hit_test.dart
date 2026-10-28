/// The edit controls in a card header look 32 and answer across 48. The 48
/// touch squares meet and never overlap: handle and Customize on top, Remove
/// under the handle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  Future<void> pumpEditing(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok(const [DiningLocation(id: 1, name: 'Crossroads', isOpen: true)]),
          events: _ok<CampusEvent>(const []),
          chefs: _ok<MenuItem>(const []),
          areas: _ok<HousingArea>(const []),
          onRefresh: () async {},
          onGoToTab: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Today'));
    await tester.pumpAndSettle();
  }

  // a card's three controls, left to right, the first card by default
  List<Finder> controls([String? title]) {
    final card = title == null ? find.byType(CardShell).first : find.ancestor(of: find.text(title), matching: find.byType(CardShell));
    return [
      find.descendant(of: card, matching: find.bySemanticsLabel('Reorder card')),
      find.descendant(of: card, matching: find.byTooltip('Customize card')),
      find.descendant(of: card, matching: find.byTooltip('Remove card from Today')),
    ];
  }

  // the controls render box a tap at [point] reaches, if any
  int? controlAt(WidgetTester tester, List<RenderObject> boxes, Offset point) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, point, tester.view.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject) continue;
      final index = boxes.indexOf(target);
      if (index >= 0) return index;
    }
    return null;
  }

  testWidgets('each control is 32 to see and 48 square to tap, and the squares never overlap', (tester) async {
    await pumpEditing(tester);
    final finders = controls();
    final boxes = [for (final f in finders) tester.renderObject(f)];
    final rects = [for (final f in finders) tester.getRect(f)];
    for (var i = 0; i < 3; i++) {
      final rect = rects[i];
      expect(rect.size, const Size(32, 32), reason: 'control $i visual');
      // 23.5 from the center is inside a 48 square, 24.5 is not
      expect(controlAt(tester, boxes, rect.center.translate(0, -23.5)), i, reason: 'control $i top');
      expect(controlAt(tester, boxes, rect.center.translate(0, 23.5)), i, reason: 'control $i bottom');
      expect(controlAt(tester, boxes, rect.center.translate(-23.5, 0)), i, reason: 'control $i left');
      expect(controlAt(tester, boxes, rect.center.translate(23.5, 0)), i, reason: 'control $i right');
    }
    // the squares meet at the edge, 48 between centers, and share no area
    final squares = [for (final r in rects) Rect.fromCenter(center: r.center, width: 48, height: 48)];
    for (var a = 0; a < 3; a++) {
      for (var b = a + 1; b < 3; b++) {
        expect(squares[a].overlaps(squares[b]), isFalse, reason: 'squares $a and $b overlap');
      }
    }
    // handle and Customize on top, Remove under the handle
    expect(rects[1].center.dx - rects[0].center.dx, 48);
    expect(rects[1].center.dy, rects[0].center.dy);
    expect(rects[2].center.dx, rects[0].center.dx);
    expect(rects[2].center.dy - rects[0].center.dy, 48);
    // either side of the line between two squares goes to its own control
    expect(controlAt(tester, boxes, Offset(rects[0].center.dx + 23.5, rects[0].center.dy)), 0);
    expect(controlAt(tester, boxes, Offset(rects[1].center.dx - 23.5, rects[1].center.dy)), 1);
    expect(controlAt(tester, boxes, Offset(rects[0].center.dx, rects[0].center.dy + 23.5)), 0);
    expect(controlAt(tester, boxes, Offset(rects[2].center.dx, rects[2].center.dy - 23.5)), 2);
  });

  testWidgets('a tap 7 above Inspect opens the card options, 7 below Remove removes a card', (tester) async {
    await pumpEditing(tester);
    // its options hold no dropdown, which overflows in the test font
    final inspect = tester.getRect(controls('Visiting chefs')[1]);
    await tester.tapAt(inspect.topCenter.translate(0, -7));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close card options'), findsOneWidget);

    final cards = find.byType(CardShell).evaluate().length;
    final remove = tester.getRect(controls()[2]);
    await tester.tapAt(remove.bottomCenter.translate(0, 7));
    await tester.pumpAndSettle();
    expect(find.byType(CardShell).evaluate().length, cards - 1);
  });

  testWidgets('the controls are an 80 by 80 block', (tester) async {
    await pumpEditing(tester);
    final card = find.byType(CardShell).first;
    final block = find.descendant(of: card, matching: find.byType(EditControls));
    expect(tester.getSize(block), const Size(editControlsWidth, editControlsHeight));
    expect(tester.getSize(block), const Size(80, 80));
  });
}
