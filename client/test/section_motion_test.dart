import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/section_nav.dart';

const sections = [
  SectionSpec(
    id: 'one',
    title: 'One',
    subtitle: 'First section',
    icon: Icons.looks_one_rounded,
    builder: firstSection,
  ),
  SectionSpec(
    id: 'two',
    title: 'Two',
    subtitle: 'Second section',
    icon: Icons.looks_two_rounded,
    builder: secondSection,
  ),
];

Widget firstSection(BuildContext context) => const Text('First content');
Widget secondSection(BuildContext context) => const Text('Second content');

Widget app({bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduceMotion,
      accessibleNavigation: reduceMotion,
    ),
    child: const Scaffold(
      body: SizedBox(
        width: 1200,
        height: 700,
        child: SectionScaffold(sections: sections, twoPaneFrom: 600),
      ),
    ),
  ),
);

void main() {
  testWidgets('wide section panes preserve both children and crossfade', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.text('First content'), findsOneWidget);
    expect(find.text('Second content'), findsNothing);
    final before = tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity, skipOffstage: false),
    );
    expect(before.map((widget) => widget.opacity), containsAll([0.0, 1.0]));

    await tester.tap(find.text('Two'));
    await tester.pump();

    final after = tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity, skipOffstage: false),
    );
    expect(after.map((widget) => widget.opacity), containsAll([0.0, 1.0]));
    expect(find.text('First content'), findsNothing);
    expect(find.text('Second content'), findsOneWidget);
  });

  testWidgets('section transition is instant with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(app(reduceMotion: true));

    final panes = tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity, skipOffstage: false),
    );
    expect(panes, hasLength(2));
    expect(panes.every((pane) => pane.duration == Duration.zero), isTrue);
  });
}
