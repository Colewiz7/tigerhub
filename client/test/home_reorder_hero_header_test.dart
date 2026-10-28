/// Edit mode on cards that have a hero.
///
/// The edit controls share the card header with the title and the hero. The
/// 80 by 80 controls block can make a card up to 48 taller in edit mode, and
/// never shorter. The gap after a card stays the same.
///
/// Covered: the real DiningCard (inline hero pill on phones) and the real
/// ScopedEventsCard (variable width text hero) on their own at the card widths
/// of a 320, 390 and 430 wide phone at 1x and 2x text, asserting the header
/// grows by 0 to 48, the pill keeps its size, the hero element is not
/// recreated, and nothing overlaps (the 320 wide 2x text hero case included:
/// the hero drops under the title when the title cannot keep its longest word
/// beside it); plus the whole dashboard with a dining hero and with a scoped
/// events text hero at 390x844 and 430x932 at 1x, asserting card 1 grows by 0
/// to 48 and the gap is equal. Not covered: the hero element surviving at
/// dashboard level, because the grid rebuilds the whole card when edit mode
/// starts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dashboard_event_cards.dart';
import 'package:tigerhub/cards/academic_dates_card.dart';
import 'package:tigerhub/cards/calendar_card.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/events_card.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart' show CardHero;

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _result<T>(List<T> data) =>
    Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

final _dining = _result([
  const DiningLocation(
    id: 1,
    name: 'Gracies',
    isOpen: true,
    category: 'dining',
    categoryName: 'Dining',
  ),
]);

const _organizer = 'Robotics Club';

final _events = _result([
  CampusEvent(
    uid: 'a',
    source: 'test',
    title: 'Meeting',
    startsAt: DateTime.utc(2099, 1, 1, 15),
    organizer: _organizer,
    organizerKey: 'swe',
  ),
  CampusEvent(
    uid: 'b',
    source: 'test',
    title: 'Workshop',
    startsAt: DateTime.utc(2099, 1, 2, 15),
    organizer: _organizer,
    organizerKey: 'swe',
  ),
]);

ThemeData _theme() => AppTheme.from(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFF4A6572),
    brightness: Brightness.light,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  void phoneView(
    WidgetTester tester, {
    required double width,
    required double height,
    required double scale,
    double ratio = 1,
  }) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(width * ratio, height * ratio);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Widget edit() =>
      EditControls(selected: false, onInspect: () {}, onRemove: () {});

  // A card at the phone's card width in a box tall enough that no content
  // overflows, so only the header is under test.
  Future<void> pumpCard(
    WidgetTester tester,
    double viewWidth,
    Widget card,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: viewWidth - 28, height: 2400, child: card),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Where the card's content starts, so the header above it has a height.
  double contentTop(WidgetTester tester, Finder shell) => tester
      .getTopLeft(
        // The shell's content is the subtree keyed on its priming state.
        find
            .descendant(
              of: shell,
              matching: find.byWidgetPredicate(
                (w) => w is KeyedSubtree && w.key is ValueKey<bool>,
              ),
            )
            .first,
      )
      .dy;

  void expectNoOverlap(
    WidgetTester tester, {
    required Finder shell,
    required Finder title,
    required Finder hero,
  }) {
    final card = tester.getRect(shell);
    Finder inCard(Finder f) => find.descendant(of: shell, matching: f);
    final named = {
      'handle': Rect.fromCenter(
        center: tester.getCenter(
          inCard(find.byIcon(Icons.drag_indicator_rounded)),
        ),
        width: 32,
        height: 32,
      ),
      'inspect': tester.getRect(inCard(find.byTooltip('Customize card'))),
      'remove': tester.getRect(
        inCard(find.byTooltip('Remove card from Today')),
      ),
      'title': tester.getRect(title),
      'hero': tester.getRect(hero),
    };
    for (final a in named.entries) {
      expect(card.contains(a.value.topLeft), isTrue, reason: a.key);
      expect(card.contains(a.value.bottomRight), isTrue, reason: a.key);
      for (final b in named.entries) {
        if (a.key.compareTo(b.key) >= 0) continue;
        expect(
          a.value.overlaps(b.value),
          isFalse,
          reason: '${a.key} ${a.value} overlaps ${b.key} ${b.value}',
        );
      }
    }
  }

  final cards = <String, ({Widget Function(Widget?) build, Finder hero})>{
    'dining badge hero': (
      build: (handle) => DiningCard(result: _dining, dragHandle: handle),
      hero: find.byType(CardHero),
    ),
    // every other hero a card passes: the events, chefs, calendar and academic
    // dates pills (scalloped badges at 600 and wider)
    'events today hero': (
      build: (handle) => EventsCard(result: _events, dragHandle: handle),
      hero: find.byType(CardHero),
    ),
    'chefs count hero': (
      build: (handle) => VisitingChefsCard(
        result: _result([
          const MenuItem(id: 1, locationName: 'Gracies', name: 'Chef Marco'),
          const MenuItem(id: 2, locationName: 'Crossroads', name: 'Chef Ayana'),
        ]),
        dragHandle: handle,
      ),
      hero: find.byType(CardHero),
    ),
    'calendar week hero': (
      build: (handle) => CalendarCard(result: _events, dragHandle: handle),
      hero: find.byType(CardHero),
    ),
    'academic dates hero': (
      build: (handle) => AcademicDatesCard(dragHandle: handle),
      hero: find.byType(CardHero),
    ),
    'scoped events text hero': (
      build: (handle) => ScopedEventsCard(
        result: _events,
        organizerKey: 'swe',
        dragHandle: handle,
      ),
      hero: find.text('2 events'),
    ),
  };

  for (final card in cards.entries) {
    for (final width in [320.0, 390.0, 430.0, 700.0, 1000.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${card.key} at $width wide, text ${scale}x: edit mode grows the '
          'header by at most 48 and nothing overlaps',
          (tester) async {
            phoneView(tester, width: width, height: 4000, scale: scale);
            final shell = find.byType(CardShell);

            await pumpCard(tester, width, card.value.build(null));
            expect(card.value.hero, findsOneWidget);
            final normal = contentTop(tester, shell);
            final normalHero = tester.getSize(card.value.hero);
            final heroElement = tester.element(card.value.hero);

            await pumpCard(tester, width, card.value.build(edit()));
            final edited = contentTop(tester, shell);
            expect(edited - normal, inInclusiveRange(0, 48));

            // The hero is the same element, so toggling edit mode does not
            // recreate it and replay its entrance.
            expect(
              identical(tester.element(card.value.hero), heroElement),
              isTrue,
            );
            // Never hidden, and a badge never shrinks below its size.
            final heroSize = tester.getSize(card.value.hero);
            expect(heroSize.width, greaterThan(0));
            expect(heroSize.height, greaterThan(0));
            // (at 600 and wider the base header may scale a hero down as a
            // last resort, so that is only asserted for dining there)
            if (card.key.startsWith('dining') ||
                (width < 600 && card.key != 'scoped events text hero')) {
              expect(heroSize, normalHero);
            }

            expectNoOverlap(
              tester,
              shell: shell,
              title: find
                  .descendant(of: shell, matching: find.byType(Text))
                  .first,
              hero: card.value.hero,
            );
          },
        );
      }
    }
  }

  testWidgets('a long title wraps by whole words and is never cut', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    phoneView(tester, width: 390, height: 4000, scale: 2);
    await pumpCard(
      tester,
      390,
      ScopedEventsCard(
        result: _events,
        organizerKey: 'swe',
        dragHandle: edit(),
      ),
    );

    final title = find.textContaining('Robotics');
    final text = tester.widget<Text>(title);
    expect(text.data, _organizer);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getSemantics(title).label, _organizer);
    handle.dispose();
  });

  for (final scoped in [false, true]) {
    for (final view in const [Size(390, 844), Size(430, 932)]) {
      testWidgets(
        'dashboard with a ${scoped ? 'scoped events text' : 'dining'} hero at '
        '${view.width.toInt()}x${view.height.toInt()}, 1x: edit mode grows '
        'card 1 by at most 48 and keeps the gap',
        (tester) async {
          phoneView(
            tester,
            width: view.width,
            height: view.height,
            scale: 1,
            ratio: 3,
          );
          if (scoped) {
            // Card 1 is a club's events card, whose hero is the text
            // "2 events"; the dining card follows it.
            await DashboardStore.save(const [
              CardInstance(
                id: 'club-1',
                type: ModuleType.clubEvents,
                scope: 'swe',
              ),
              CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
            ]);
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: _theme(),
              home: Scaffold(
                body: HomeScreen(
                  api: ApiClient(backend: _EmptyBackend()),
                  dining: _dining,
                  events: scoped ? _events : _result<CampusEvent>(const []),
                  chefs: _result<MenuItem>(const []),
                  areas: _result<HousingArea>(const []),
                  onRefresh: () async {},
                  onGoToTab: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final hero = scoped
              ? find.descendant(
                  of: find.byType(CardShell).first,
                  matching: find.text('2 events'),
                )
              : find.byType(CardHero);
          expect(hero, findsOneWidget);
          ({double height, double gap}) measure() {
            final first = tester.getRect(find.byType(CardShell).at(0));
            final second = tester.getRect(find.byType(CardShell).at(1));
            return (height: first.height, gap: second.top - first.bottom);
          }

          final normal = measure();

          final position = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit Today'));
          await tester.pumpAndSettle();
          position.jumpTo(0);
          await tester.pumpAndSettle();

          final edited = measure();
          // Not asserted here: that the hero element survives. The grid
          // rebuilds the whole card when edit mode starts, so that only holds
          // for the header, which the card level tests above cover.
          expect(edited.height - normal.height, inInclusiveRange(0, 48));
          expect(edited.gap, normal.gap);
          expectNoOverlap(
            tester,
            shell: find.byType(CardShell).first,
            title: find
                .descendant(
                  of: find.byType(CardShell).first,
                  matching: find.byType(Text),
                )
                .first,
            hero: hero,
          );
        },
      );
    }
  }
}
