/// Drives a context menu end to end and checks what each item really does.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/context_actions.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

sealed class MenuEffect {
  const MenuEffect();
}

class Copies extends MenuEffect {
  const Copies(this.text);
  final String text;
}

class Launches extends MenuEffect {
  const Launches(this.url);
  final String url;
}

class Mutes extends MenuEffect {
  const Mutes(this.key, this.name);
  final String key;
  final String name;
}

class Unmutes extends MenuEffect {
  const Unmutes(this.key);
  final String key;
}

// pin and hide say where the place should end up
class SetsPinned extends MenuEffect {
  const SetsPinned(this.id, this.pinned);
  final int id;
  final bool pinned;
}

class SetsHidden extends MenuEffect {
  const SetsHidden(this.id, this.hidden, {this.name});
  final int id;
  final bool hidden;
  // set when hiding speaks and offers Undo
  final String? name;
}

class OpensMoveSheet extends MenuEffect {
  const OpensMoveSheet();
}

// a Campus row leaves the list, speaks and offers Undo
class HidesCampusRow extends MenuEffect {
  const HidesCampusRow(this.name);
  final String name;
}

class MenuSurface {
  const MenuSurface({
    required this.name,
    required this.files,
    required this.build,
    required this.target,
    required this.labels,
    required this.effects,
    this.prepare,
    this.arrange,
  });

  // runs before the first build, for state a row reads once
  final Future<void> Function()? arrange;

  final String name;

  // lib files that construct menu actions, checked against the source
  final List<String> files;
  final Widget Function() build;
  final Future<void> Function(WidgetTester tester)? prepare;
  final Finder Function() target;
  final List<String> labels;
  final Map<String, MenuEffect> effects;
}

class _FakeLauncher extends MethodChannelUrlLauncher with MockPlatformInterfaceMixin {
  final launched = <String>[];
  var succeeds = true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return succeeds;
  }
}

// stands in for the platform: clipboard, haptics, announcements, launcher
class MenuProbe {
  final clipboard = <String>[];
  final haptics = <String>[];
  final announcements = <String>[];
  final _launcher = _FakeLauncher();

  List<String> get launched => _launcher.launched;

  // a platform with no dialer or mail client
  set launcherWorks(bool works) => _launcher.succeeds = works;

  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
      final map = message as Map;
      if (map['type'] == 'announce') announcements.add((map['data'] as Map)['message'] as String);
      return null;
    });
    UrlLauncherPlatform.instance = _launcher;
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null);
    });
  }

  void clear() {
    clipboard.clear();
    haptics.clear();
    announcements.clear();
    launched.clear();
  }
}

ThemeData menuTheme({bool dark = false}) => AppTheme.from(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFFF76902),
    brightness: dark ? Brightness.dark : Brightness.light,
  ),
);

Future<void> pumpSurface(
  WidgetTester tester,
  MenuSurface surface, {
  Size size = const Size(390, 844),
  bool dark = false,
  double textScale = 1.0,
  Key? boundaryKey,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await surface.arrange?.call();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: menuTheme(dark: dark),
        home: Scaffold(body: surface.build()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await surface.prepare?.call(tester);
  await tester.pumpAndSettle();
}

// lazy lists at 2x text leave rows unbuilt or below the fold
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 120, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> secondaryTap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> longPress(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.longPress(target);
  await tester.pumpAndSettle();
}

// focuses the row's own stop, then presses the key the way a keyboard would
Future<void> keyboardOpen(WidgetTester tester, Finder target, {bool shiftF10 = false}) async {
  await reveal(tester, target);
  final wrapper = find.ancestor(of: target, matching: find.byType(ContextActions)).first.evaluate().single;
  for (final node in FocusManager.instance.rootScope.traversalDescendants) {
    var inside = false;
    node.context?.visitAncestorElements((ancestor) {
      inside = ancestor == wrapper;
      return !inside;
    });
    if (!inside) continue;
    node.requestFocus();
    break;
  }
  await tester.pump();
  if (shiftF10) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
  }
  await tester.pumpAndSettle();
}

Finder get menuItems => find.byType(PopupMenuItem<int>);

List<String> menuLabels(WidgetTester tester) => [
  for (final item in menuItems.evaluate())
    tester.widget<Text>(find.descendant(of: find.byWidget(item.widget), matching: find.byType(Text))).data!,
];

Future<void> tapMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: menuItems, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> expectMenuOpen(WidgetTester tester, List<String> labels) async {
  expect(menuLabels(tester), labels);
  for (final item in menuItems.evaluate()) {
    expect(tester.getSize(find.byWidget(item.widget)).height, greaterThanOrEqualTo(48));
  }
}

Future<void> expectMenuClosed(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(menuItems, findsNothing);
}

void expectEffect(WidgetTester tester, MenuProbe probe, MenuEffect effect, String label) {
  switch (effect) {
    case Copies(:final text):
      expect(probe.clipboard, [text], reason: '$label clipboard');
      expect(find.text('Copied'), findsOneWidget, reason: '$label snackbar');
      expect(probe.announcements, ['Copied'], reason: '$label announcement');
    case Launches(:final url):
      expect(probe.launched, [url], reason: '$label launch');
      expect(probe.clipboard, isEmpty, reason: '$label should not fall back to copy');
    case Mutes(:final key, :final name):
      expect(Preferences.instance.mutedOrganizers, contains(key), reason: '$label mute');
      expect(find.text('Muted $name'), findsOneWidget, reason: '$label snackbar');
      expect(find.text('Undo'), findsOneWidget, reason: '$label undo');
      expect(probe.announcements, ['Muted $name'], reason: '$label announcement');
    case Unmutes(:final key):
      expect(Preferences.instance.mutedOrganizers, isNot(contains(key)), reason: '$label unmute');
    case SetsPinned(:final id, :final pinned):
      expect(Preferences.instance.isPinned(id), pinned, reason: '$label pin');
    case SetsHidden(:final id, :final hidden, :final name):
      expect(Preferences.instance.isHidden(id), hidden, reason: '$label hide');
      if (name != null) {
        expect(find.text('Hid $name'), findsOneWidget, reason: '$label snackbar');
        expect(find.text('Undo'), findsOneWidget, reason: '$label undo');
        expect(probe.announcements, ['Hid $name'], reason: '$label announcement');
      }
    case OpensMoveSheet():
      expect(find.text('Move to group'), findsWidgets, reason: '$label sheet');
      expect(find.text('Dorm side'), findsOneWidget, reason: '$label lists the groups');
    case HidesCampusRow(:final name):
      expect(Preferences.instance.campusLayout.hasHidden, isTrue, reason: '$label hide');
      expect(find.text('Hid $name'), findsOneWidget, reason: '$label snackbar');
      expect(find.text('Undo'), findsOneWidget, reason: '$label undo');
      expect(probe.announcements, ['Hid $name'], reason: '$label announcement');
  }
}

Future<void> resetAfterEffect(WidgetTester tester, MenuProbe probe, MenuEffect effect) async {
  if (effect case Mutes(:final key)) await Preferences.instance.setMuted(key, false);
  if (effect case Unmutes(:final key)) await Preferences.instance.setMuted(key, true);
  if (effect case SetsPinned(:final id)) await Preferences.instance.togglePinned(id);
  if (effect case SetsHidden(:final id)) await Preferences.instance.toggleHidden(id);
  if (effect is HidesCampusRow) await Preferences.instance.resetCampus();
  if (effect is OpensMoveSheet) {
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  }
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  probe.clear();
}

// the whole table check for one surface: labels, every effect, close paths
Future<void> checkSurface(WidgetTester tester, MenuSurface surface) async {
  expect(surface.effects.keys.toSet(), surface.labels.toSet(), reason: '${surface.name} declares an effect per label');
  final probe = MenuProbe()..install(tester);
  final semantics = tester.ensureSemantics();
  await pumpSurface(tester, surface);

  await secondaryTap(tester, surface.target());
  await expectMenuOpen(tester, surface.labels);
  expect(probe.haptics, ['HapticFeedbackType.lightImpact'], reason: 'one light haptic on open');
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await expectMenuClosed(tester);

  await longPress(tester, surface.target());
  await expectMenuOpen(tester, surface.labels);
  await tester.tapAt(const Offset(2, 2));
  await expectMenuClosed(tester);

  for (final label in surface.labels) {
    final effect = surface.effects[label]!;

    probe.clear();
    await secondaryTap(tester, surface.target());
    await tapMenuItem(tester, label);
    await expectMenuClosed(tester);
    expectEffect(tester, probe, effect, label);
    await resetAfterEffect(tester, probe, effect);

    // same action through the screen reader path
    final node = tester.getSemantics(find.ancestor(of: surface.target(), matching: find.byType(ContextActions)).first);
    final action = node.getSemanticsData().customSemanticsActionIds!.map(CustomSemanticsAction.getAction).firstWhere((a) => a!.label == label);
    node.owner!.performAction(node.id, SemanticsAction.customAction, CustomSemanticsAction.getIdentifier(action!));
    await tester.pumpAndSettle();
    expectEffect(tester, probe, effect, '$label via semantics');
    await resetAfterEffect(tester, probe, effect);
  }
  semantics.dispose();
}
