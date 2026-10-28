import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/settings/settings_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

import 'golden_harness.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester, Size size, Brightness brightness, double scale, {TargetPlatform? platform}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    addTearDown(scheme.dispose);
    await tester.pumpWidget(Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          theme: AppTheme.from(SchemeController.builtIn(brightness)).copyWith(platform: platform),
          home: Scaffold(
            body: SettingsScreen(
              scheme: scheme,
              events: const Result<Collection<CampusEvent>>(
                value: null,
                state: DataState.priming,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final size in const [Size(390, 844), Size(430, 932)]) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 2.0]) {
        final name = 'settings_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x.png';
        goldenWidgets(name, (tester) async {
          await pumpSettings(tester, size, brightness, scale);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
        });
      }
    }
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 2.0]) {
        final name = 'settings_ios_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x.png';
        goldenWidgets(name, (tester) async {
          await pumpSettings(tester, size, brightness, scale, platform: TargetPlatform.iOS);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
        });
      }
    }
  }

  testWidgets('settings has no home card controls', (tester) async {
    await pumpSettings(tester, const Size(390, 844), Brightness.light, 1);
    expect(find.text('Home screen'), findsNothing);
    expect(find.text('Card order'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });
}
