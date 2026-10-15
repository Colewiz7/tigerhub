/// Empty states sit in the middle of their dashboard card, both ways, at every
/// text scale: Dining, Events, Mailing Address and Visiting Chefs, on a phone
/// (cards as tall as their content) and on a tablet (fixed height cells).
///
/// "Middle" is the middle of the card's content slot, the room under the
/// header: the mark and sentence block is centered in it, and the slot spans
/// the card's full inner width, so the block is centered across the card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/empty_state.dart';

import 'golden_harness.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _empty<T>() => Result(
  value: Collection<T>(data: const [], stale: false),
  state: DataState.ok,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final size in const [Size(390, 844), Size(440, 956), Size(700, 1000)]) {
    for (final scale in const [1.0, 2.0]) {
      goldenWidgets(
        'empty states are centered in their cards at '
        '${size.width.toInt()}x${size.height.toInt()}, text ${scale}x',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.from(
                ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
              ),
              home: Scaffold(
                body: HomeScreen(
                  api: ApiClient(backend: _EmptyBackend()),
                  dining: _empty<DiningLocation>(),
                  events: _empty<CampusEvent>(),
                  chefs: _empty<MenuItem>(),
                  areas: _empty<HousingArea>(),
                  onRefresh: () async {},
                  onGoToTab: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          final shells = find.byType(CardShell);
          expect(shells, findsNWidgets(4));
          for (var i = 0; i < 4; i++) {
            // bring the card on screen; hit testing is not needed, geometry is
            scroll.jumpTo(0);
            await tester.pumpAndSettle();
            final shell = shells.at(i);
            final card = tester.getRect(shell);
            final empty = find.descendant(
              of: shell,
              matching: find.byType(EmptyState),
            );
            expect(empty, findsOneWidget, reason: 'card $i');
            final slot = tester.getRect(empty);
            final block = tester.getRect(
              find.descendant(of: empty, matching: find.byType(Column)).first,
            );

            // across: the slot is the card's inner width and the block is in
            // the middle of it, so the block is in the middle of the card
            expect(
              (slot.center.dx - card.center.dx).abs(),
              lessThan(1),
              reason: 'card $i slot is off center across the card',
            );
            expect(
              (block.center.dx - card.center.dx).abs(),
              lessThan(1),
              reason: 'card $i block $block is off center across $card',
            );
            // down: equal room above and below the block in the slot
            expect(
              (block.top - slot.top - (slot.bottom - block.bottom)).abs(),
              lessThan(1),
              reason: 'card $i block $block is off center down slot $slot',
            );
            expect(slot.top, greaterThanOrEqualTo(card.top));
            expect(slot.bottom, lessThanOrEqualTo(card.bottom));
          }
        },
      );
    }
  }
}
