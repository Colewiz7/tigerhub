/// Every surface that ships a context menu, with the labels and effects it must have.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/academic_dates_card.dart';
import 'package:tigerhub/cards/dashboard_campus_cards.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/shuttles.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/services/academic_dates.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/widgets/event_details_sheet.dart';
import 'package:tigerhub/widgets/freshness.dart';
import 'package:tigerhub/widgets/shuttle_routes_sheet.dart';

import 'context_menu_harness.dart';

class _FixtureBackend implements Backend {
  _FixtureBackend(this.config);

  final StaticConfig config;

  Map<String, dynamic> _envelope(List<dynamic> data) => {'data': data, 'stale': false, 'last_updated': null};

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    switch (path) {
      case '/post-offices':
        return _envelope(config.postOffices);
      case '/housing/areas':
        return _envelope(config.housingAreas);
      case '/makerspace/hours':
        return {'items': config.shedSpaces};
      case '/makerspace/rooms':
        return _envelope([
          {'room': 'Wood Shop', 'machines': 15, 'available': 12, 'in_use': 3},
        ]);
      case '/recreation/hours':
        return _envelope(recreationFacilities({'rows': _recRows()}));
    }
    // the housing card asks for the mailing address once a home is set, and an empty envelope is not one
    if (path.startsWith('/housing/')) throw UnimplementedError(path);
    return _envelope(const []);
  }

  @override
  void close() {}
}

List<Map<String, dynamic>> _recRows() => parseRecreation(File('test/fixtures/recreation.html').readAsStringSync(), today: DateTime.utc(2026, 8, 30));

// the same pinned day the campus screen tests use
final _day = DateTime(2026, 8, 30);

Future<void> prepareMenuEnvironment() async {
  final files = <String, Map<String, dynamic>>{};
  for (final name in ['dining_categories', 'dining_groups', 'post_offices', 'housing_areas', 'shed_hours', 'fd_locations']) {
    files[name] = jsonDecode(File('assets/config/$name.json').readAsStringSync()) as Map<String, dynamic>;
  }
  StaticConfig.overrideForTesting(files);
  ShuttleSchedule.overrideForTesting(ShuttleSchedule.parse(jsonDecode(File('assets/config/shuttles.json').readAsStringSync()) as Map<String, dynamic>));
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  RitClock.pin(CampusTime.wall(2026, 8, 30, 12));
  Preferences.instance.resetForTests();
  await Preferences.instance.setHome(area: 'global-village');
  await Preferences.instance.setMuted('student-life', false);
}

Widget _campus() {
  final config = StaticConfig.instance;
  return CampusScreen(
    api: ApiClient(backend: _FixtureBackend(config)),
    now: _day,
    areas: Result(
      value: Collection(data: config.housingAreas.map(HousingArea.fromJson).toList(), stale: false),
      state: DataState.ok,
    ),
  );
}

Future<void> Function(WidgetTester) _section(String title) => (tester) async {
  await reveal(tester, find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
};

final _event = CampusEvent(
  uid: 'open-mic',
  source: 'test',
  title: 'Open mic night',
  startsAt: CampusTime.wall(2026, 8, 31, 19),
  location: 'Ritz Sports Zone',
  organizer: 'Student Life',
  organizerKey: 'student-life',
  url: 'https://example.edu/events/open-mic',
);

final _noLinkEvent = CampusEvent(
  uid: 'open-mic',
  source: 'test',
  title: 'Open mic night',
  startsAt: CampusTime.wall(2026, 8, 31, 19),
  location: 'Ritz Sports Zone',
  organizer: 'Student Life',
  organizerKey: 'student-life',
);

Widget _eventRow(CampusEvent event) => Padding(padding: const EdgeInsets.all(8), child: Align(alignment: Alignment.topCenter, child: EventRow(event: event, now: CampusTime.wall(2026, 8, 30, 12))));

AcademicMilestone get _firstDate => upcomingAcademicMilestones(now: _day).first;

String _dateText(AcademicMilestone m, String pattern) => '${m.title}\n${m.dateText(DateFormat(pattern))}\n${m.detail}';

Widget _diningRow() => Padding(
  padding: const EdgeInsets.all(8),
  child: Align(
    alignment: Alignment.topCenter,
    child: DiningRow(location: const DiningLocation(id: 21, name: "Gracie's", isOpen: true), api: ApiClient(backend: _FixtureBackend(StaticConfig.instance))),
  ),
);

final menuSurfaces = <MenuSurface>[
  MenuSurface(
    name: 'dining row',
    files: const ['lib/widgets/dining_actions.dart'],
    build: _diningRow,
    target: () => find.text("Gracie's"),
    labels: const ['Pin', 'Hide', 'Move to group'],
    effects: const {
      'Pin': SetsPinned(21, true),
      'Hide': SetsHidden(21, true, name: "Gracie's"),
      'Move to group': OpensMoveSheet(),
    },
  ),
  MenuSurface(
    name: 'pinned dining row',
    files: const ['lib/widgets/dining_actions.dart'],
    build: _diningRow,
    arrange: () => Preferences.instance.togglePinned(21),
    target: () => find.text("Gracie's"),
    labels: const ['Unpin', 'Hide', 'Move to group'],
    effects: const {
      'Unpin': SetsPinned(21, false),
      'Hide': SetsHidden(21, true, name: "Gracie's"),
      'Move to group': OpensMoveSheet(),
    },
  ),
  MenuSurface(
    name: 'hidden dining row',
    files: const ['lib/widgets/dining_actions.dart'],
    build: _diningRow,
    arrange: () => Preferences.instance.toggleHidden(21),
    target: () => find.text("Gracie's"),
    labels: const ['Unhide', 'Move to group'],
    effects: const {
      'Unhide': SetsHidden(21, false),
      'Move to group': OpensMoveSheet(),
    },
  ),
  MenuSurface(
    name: 'event row',
    files: const ['lib/cards/event_row.dart'],
    build: () => _eventRow(_event),
    target: () => find.text('Open mic night'),
    labels: const ['Copy title', 'Copy details', 'Open page', 'Mute organizer'],
    effects: {
      'Copy title': const Copies('Open mic night'),
      'Copy details': Copies(eventShareText(_event, formatDayAndClock(_event.startsAt))),
      'Open page': const Launches('https://example.edu/events/open-mic'),
      'Mute organizer': const Mutes('student-life', 'Student Life'),
    },
  ),
  MenuSurface(
    name: 'event row without a link',
    files: const ['lib/cards/event_row.dart'],
    build: () => _eventRow(_noLinkEvent),
    target: () => find.text('Open mic night'),
    labels: const ['Copy title', 'Copy details', 'Mute organizer'],
    effects: {
      'Copy title': const Copies('Open mic night'),
      'Copy details': Copies(eventShareText(_noLinkEvent, formatDayAndClock(_noLinkEvent.startsAt))),
      'Mute organizer': const Mutes('student-life', 'Student Life'),
    },
  ),
  MenuSurface(
    name: 'event row from a muted organizer',
    files: const ['lib/cards/event_row.dart'],
    build: () => _eventRow(_event),
    arrange: () => Preferences.instance.setMuted('student-life', true),
    target: () => find.text('Open mic night'),
    labels: const ['Copy title', 'Copy details', 'Open page', 'Unmute organizer'],
    effects: {
      'Copy title': const Copies('Open mic night'),
      'Copy details': Copies(eventShareText(_event, formatDayAndClock(_event.startsAt))),
      'Open page': const Launches('https://example.edu/events/open-mic'),
      'Unmute organizer': const Unmutes('student-life'),
    },
  ),
  MenuSurface(
    name: 'academic dates card row',
    files: const ['lib/cards/academic_dates_card.dart'],
    build: () => const SingleChildScrollView(child: AcademicDatesCard()),
    target: () => find.text(_firstDate.title),
    labels: const ['Copy text'],
    effects: {'Copy text': Copies(_dateText(_firstDate, 'MMM d'))},
  ),
  MenuSurface(
    name: 'academic dates row',
    files: const ['lib/screens/campus_screen.dart'],
    build: _campus,
    prepare: _section('Academic dates'),
    target: () => find.text(_firstDate.title),
    labels: const ['Copy text'],
    effects: {'Copy text': Copies(_dateText(_firstDate, 'EEE, MMM d'))},
  ),
  MenuSurface(
    name: 'bus route row',
    files: const ['lib/widgets/shuttle_routes_sheet.dart'],
    build: () => const SingleChildScrollView(child: ShuttleRoutesSheet()),
    target: () => find.textContaining('13 · Campus & Inn'),
    labels: const ['Copy text'],
    effects: const {'Copy text': Copies('13 · Campus & Inn Shuttle\n7:47 AM–12:33 AM')},
  ),
  MenuSurface(
    name: 'safety contact row',
    files: const ['lib/screens/campus_screen.dart'],
    build: _campus,
    prepare: _section('Safety'),
    target: () => find.text('Emergency call'),
    labels: const ['Call', 'Copy number'],
    effects: const {'Call': Launches('tel:5854753333'), 'Copy number': Copies('585-475-3333')},
  ),
  MenuSurface(
    name: 'safety text contact row',
    files: const ['lib/screens/campus_screen.dart'],
    build: _campus,
    prepare: _section('Safety'),
    target: () => find.text('Emergency text'),
    labels: const ['Text', 'Copy number'],
    effects: const {'Text': Launches('sms:5852058333'), 'Copy number': Copies('585-205-8333')},
  ),
  MenuSurface(
    name: 'makerspace room row',
    files: const ['lib/screens/campus_screen.dart'],
    build: _campus,
    prepare: _section('SHED makerspace'),
    target: () => find.text('Wood Shop'),
    labels: const ['Copy text'],
    effects: const {'Copy text': Copies('Wood Shop\n15 machines, 12 free')},
  ),
  MenuSurface(
    name: 'recreation row',
    files: const ['lib/screens/campus_screen.dart'],
    build: _campus,
    prepare: _section('Gym and pool'),
    target: () => find.text('Judson/Hale Aquatics Center'),
    labels: const ['Copy text', 'Hide'],
    effects: const {
      'Copy text': Copies('Judson/Hale Aquatics Center\n2:30 PM to 4:30 PM,  7:00 PM to 10:00 PM'),
      'Hide': HidesCampusRow('Judson/Hale Aquatics Center'),
    },
  ),
  MenuSurface(
    name: 'campus nav row',
    files: const ['lib/widgets/campus_actions.dart'],
    build: _campus,
    target: () => find.text('Quick links'),
    labels: const ['Hide'],
    effects: const {'Hide': HidesCampusRow('Quick links')},
  ),
  MenuSurface(
    name: 'post office block',
    files: const ['lib/screens/campus_screen.dart'],
    build: _campus,
    prepare: _section('Mail'),
    target: () => find.text('Global Village Post Office'),
    labels: const ['Hide'],
    effects: const {'Hide': HidesCampusRow('Global Village Post Office')},
  ),
  MenuSurface(
    name: 'facility card row',
    files: const ['lib/cards/dashboard_campus_cards.dart'],
    build: () => const Align(alignment: Alignment.topCenter, child: SizedBox(height: 700, child: _FacilityCardHost())),
    target: () => find.text('Aquatics Center').last,
    labels: const ['Copy text'],
    effects: const {'Copy text': Copies('Aquatics Center\n8:00 AM to 8:00 PM')},
  ),
];

class _FacilityCardHost extends StatelessWidget {
  const _FacilityCardHost();

  @override
  Widget build(BuildContext context) => FacilityHoursCard(
    facilityName: 'Aquatics Center',
    result: Result(
      value: Collection(
        data: [
          RecreationFacility(
            name: 'Aquatics Center',
            days: [
              RecreationDay(
                serviceDate: _day,
                closed: false,
                spans: const [RecreationSpan(opensAt: '08:00', closesAt: '20:00')],
              ),
            ],
          ),
        ],
        stale: false,
      ),
      state: DataState.ok,
    ),
  );
}
