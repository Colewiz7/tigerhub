/// Card names in sentence case, the same in the library and on the card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/academic_dates_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

void main() {
  test('the library names each card in sentence case', () {
    expect(moduleLabels[ModuleType.diningStatus], 'Eat now');
    expect(moduleLabels[ModuleType.generalEvents], 'Up next');
    expect(moduleLabels[ModuleType.visitingChefs], 'Visiting chefs');
    expect(moduleLabels[ModuleType.mailingAddress], 'Mailing address');
    expect(moduleLabels[ModuleType.academicDates], 'Academic dates');
    // only the first word and proper nouns take a capital
    for (final label in moduleLabels.values) {
      final words = label.split(' ');
      for (final word in words.skip(1)) {
        expect(word == word.toLowerCase(), isTrue, reason: label);
      }
    }
  });

  for (final width in [390.0, 700.0]) {
    testWidgets('the cards say it the same way at $width wide', (tester) async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(
          body: HomeScreen(
            api: ApiClient(backend: _EmptyBackend()),
            dining: _ok<DiningLocation>(const []),
            events: _ok<CampusEvent>(const []),
            chefs: _ok(const [MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A')]),
            areas: _ok<HousingArea>(const []),
            onRefresh: () async {},
            onGoToTab: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Visiting chefs'), findsOneWidget);
      expect(find.text('Mailing address'), findsOneWidget);
      expect(find.text('Visiting Chefs'), findsNothing);
      expect(find.text('Mailing Address'), findsNothing);
    });
  }

  testWidgets('academic dates is sentence case', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: const Scaffold(body: SingleChildScrollView(child: AcademicDatesCard())),
    ));
    await tester.pump();
    expect(find.text('Academic dates'), findsOneWidget);
  });
}
