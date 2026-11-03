/// The Privacy policy and Support rows in About open the site pages in the
/// browser, never inside the app, and copy the link when nothing can open it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tigerhub/screens/settings/about_section.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends MethodChannelUrlLauncher with MockPlatformInterfaceMixin {
  _Launcher({required this.succeeds});

  final bool succeeds;
  final opened = <String>[];
  final modes = <PreferredLaunchMode>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    modes.add(options.mode);
    return succeeds;
  }
}

void main() {
  const privacy = 'https://colewiz7.github.io/tigerhub-site/privacy.html';
  const support = 'https://colewiz7.github.io/tigerhub-site/support.html';

  late UrlLauncherPlatform previous;

  setUp(() => previous = UrlLauncherPlatform.instance);
  tearDown(() => UrlLauncherPlatform.instance = previous);

  Future<void> pumpAbout(WidgetTester tester, {double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          theme: AppTheme.from(SchemeController.builtIn(Brightness.light)),
          home: const Scaffold(body: AboutSection()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Privacy policy opens the policy page externally', (tester) async {
    final launcher = _Launcher(succeeds: true);
    UrlLauncherPlatform.instance = launcher;
    await pumpAbout(tester);

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(launcher.opened, [privacy]);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
  });

  testWidgets('Support opens the support page externally', (tester) async {
    final launcher = _Launcher(succeeds: true);
    UrlLauncherPlatform.instance = launcher;
    await pumpAbout(tester);

    await tester.tap(find.text('Support'));
    await tester.pump();

    expect(launcher.opened, [support]);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
  });

  testWidgets('a failed launch copies the link and says so', (tester) async {
    UrlLauncherPlatform.instance = _Launcher(succeeds: false);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpAbout(tester);

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, privacy);
    expect(find.text('Privacy policy link copied'), findsOneWidget);
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('both rows are 48pt targets with labels at ${scale}x', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAbout(tester, scale: scale);

      for (final key in const ['about-privacy', 'about-support']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
      const labels = {'about-privacy': 'Privacy policy', 'about-support': 'Support'};
      labels.forEach((key, label) {
        final node = tester.getSemantics(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(InkWell)),
        );
        expect(node.label, startsWith(label), reason: key);
        expect(node.hint, contains('Opens externally'), reason: key);
      });
      handle.dispose();
    });
  }

  test('the copy has no em dash and is sentence case', () {
    for (final text in const ['Privacy policy', 'Support']) {
      expect(text, isNot(contains('—')));
      expect(text, text[0].toUpperCase() + text.substring(1).toLowerCase());
    }
  });
}
