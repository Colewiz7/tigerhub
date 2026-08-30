import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/arc_progress.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/freshness.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

Widget wrap(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduceMotion,
      accessibleNavigation: reduceMotion,
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('priming is a static skeleton, not a spinner', (tester) async {
    await tester.pumpWidget(
      wrap(const PrimingPlaceholder(label: 'Loading dining hours')),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading dining hours'), findsOneWidget);
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('card transition is disabled with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const CardShell(title: 'Dining', child: Text('Ready')),
        reduceMotion: true,
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('badge value transition is disabled with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ScallopedBadge(value: '3', label: 'OPEN NOW'),
        reduceMotion: true,
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('arc tween is bypassed with reduced motion', (tester) async {
    await tester.pumpWidget(
      wrap(const ArcProgress(value: 0.6), reduceMotion: true),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('arc animates in normal motion mode', (tester) async {
    await tester.pumpWidget(wrap(const ArcProgress(value: 0.6)));

    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
  });

  testWidgets('tab indicators keep their final state with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppTabBar(
          tabs: const [
            TabSpec(icon: Icons.home_rounded, label: 'TODAY'),
            TabSpec(icon: Icons.map_rounded, label: 'CAMPUS'),
          ],
          index: 0,
          onSelect: (_) {},
        ),
        reduceMotion: true,
      ),
    );

    final indicators = tester.widgetList<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(indicators, hasLength(2));
    expect(
      indicators.every((indicator) => indicator.duration == Duration.zero),
      isTrue,
    );
  });
}
