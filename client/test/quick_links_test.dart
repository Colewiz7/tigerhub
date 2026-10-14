import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tigerhub/data/quick_links.dart';
import 'package:tigerhub/screens/quick_links_section.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends MethodChannelUrlLauncher with MockPlatformInterfaceMixin {
  final opened = <String>[];
  final modes = <PreferredLaunchMode>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    modes.add(options.mode);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedLinks = <({String label, String url})>[
    (label: 'Tiger Spend', url: 'https://tigerspend.rit.edu/'),
    (label: 'SIS', url: 'https://campus.ps.rit.edu/'),
    (label: 'myCourses', url: 'https://mycourses.rit.edu/'),
    (label: 'eServices', url: 'https://eservices.rit.edu/'),
    (label: 'Tiger Chat', url: 'https://tigerchat.app/'),
    (label: 'Service Center', url: 'https://help.rit.edu/'),
    (label: 'FMS requests', url: 'https://www.rit.edu/facilitiesmanagement/request-service'),
  ];

  setUpAll(() async {
    await (FontLoader('Rubik')..addFont(rootBundle.load('assets/fonts/Rubik.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> pumpLinks(WidgetTester tester, Size size, Brightness brightness, double scale) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final theme = AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness));
    await tester.pumpWidget(MaterialApp(
      theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Rubik')),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: const Scaffold(body: QuickLinksSection()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('every quick link renders, has semantics and opens externally', (tester) async {
    expect(quickLinks, hasLength(7));
    expect(quickLinks.map((link) => (label: link.label, url: link.url)).toList(), expectedLinks);
    for (final link in quickLinks) {
      final parsed = DateTime.tryParse(link.lastVerified);
      expect(parsed?.toIso8601String().substring(0, 10), link.lastVerified);
    }
    final launcher = _Launcher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await pumpLinks(tester, const Size(390, 844), Brightness.light, 1);

    for (final link in quickLinks) {
      final row = find.byKey(ValueKey(link.label));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == '${link.label}, ${link.subtitle ?? Uri.parse(link.url).host}' && widget.properties.hint == 'Opens externally'), findsOneWidget);
      expect(tester.getSize(row).height - 8, greaterThanOrEqualTo(48));
      await tester.tap(row);
      await tester.pump();
    }

    expect(launcher.opened, expectedLinks.map((link) => link.url).toList());
    expect(launcher.modes, everyElement(PreferredLaunchMode.externalApplication));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(390, 844), Size(430, 932)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 2.0]) {
        final name = 'quick_links_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x.png';
        testWidgets(name, (tester) async {
          await pumpLinks(tester, size, brightness, scale);
          expect(tester.takeException(), isNull);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
        });
      }
    }
  }
}
