import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'golden_harness.dart';

class _DashboardBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

void main() {
  setUpGoldenFonts();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final size in [const Size(390, 844), const Size(430, 932)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 2.0]) {
        goldenWidgets(
          'dashboard chefs ${size.width.toInt()}x${size.height.toInt()} ${brightness.name} ${scale}x',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            addTearDown(tester.view.reset);
            await DashboardStore.save(const [
              CardInstance(
                id: 'chefs-0',
                type: ModuleType.visitingChefs,
                size: CardSize.standard,
              ),
              CardInstance(
                id: 'dining-0',
                type: ModuleType.diningStatus,
                size: CardSize.standard,
              ),
            ]);

            final scheme = ColorScheme.fromSeed(
              seedColor: const Color(0xFFF76902),
              brightness: brightness,
            );
            final theme = AppTheme.from(scheme);
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: goldenTheme(theme),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: HomeScreen(
                      api: ApiClient(backend: _DashboardBackend()),
                      dining: const Result(
                        value: Collection(
                          data: [
                            DiningLocation(
                              id: 23,
                              name: 'Crossroads',
                              isOpen: true,
                            ),
                          ],
                          stale: false,
                        ),
                        state: DataState.ok,
                      ),
                      events: const Result(
                        value: Collection<CampusEvent>(data: [], stale: false),
                        state: DataState.ok,
                      ),
                      chefs: const Result(
                        value: Collection<MenuItem>(data: [], stale: false),
                        state: DataState.ok,
                      ),
                      areas: const Result(
                        value: Collection<HousingArea>(data: [], stale: false),
                        state: DataState.ok,
                      ),
                      onRefresh: () async {},
                      onGoToTab: (_) {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('No visiting chefs today'), findsOneWidget);
            expect(find.text('OPEN'), findsOneWidget);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/dashboard_chefs_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x.png',
              ),
            );
          },
        );
      }
    }
  }
}
