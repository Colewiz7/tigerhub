/// Illustrated empty states.
///
/// The failure this guards against is quiet: a missing or misnamed SVG renders
/// as a blank box rather than throwing, which looks exactly like the empty
/// state working. So every asset is loaded from the real bundle and parsed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/empty_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every empty state has its own familiar symbol', () {
    expect(
      EmptyKind.values.map((kind) => kind.icon).toSet(),
      hasLength(EmptyKind.values.length),
    );
  });

  testWidgets('renders the themed mark and copy together', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: const Scaffold(
          body: Center(child: EmptyState(kind: EmptyKind.noVisitingChefs)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The spec's copy, not something invented at the call site.
    expect(find.text('No visiting chefs today'), findsOneWidget);
    expect(find.byIcon(Icons.room_service_rounded), findsOneWidget);
  });

  testWidgets('a caller can say something more specific', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: const Scaffold(
          body: Center(
            child: EmptyState(
              kind: EmptyKind.sourceDown,
              title: 'Dining is unavailable',
              detail: 'Last checked a moment ago',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dining is unavailable'), findsOneWidget);
    expect(find.text('Last checked a moment ago'), findsOneWidget);
    expect(
      find.text('This source is unavailable'),
      findsNothing,
      reason: 'an override should replace the default, not sit beside it',
    );
  });

  testWidgets('the art is not announced to a screen reader', (tester) async {
    // The copy underneath already says what the state is. Announcing the
    // drawing as well would say it twice.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: const Scaffold(
          body: Center(child: EmptyState(kind: EmptyKind.noEvents)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('no events')), findsNothing);
    expect(
      find.bySemanticsLabel('Nothing scheduled today'),
      findsOneWidget,
      reason: 'the caption is what should be announced',
    );
    handle.dispose();
  });
}
