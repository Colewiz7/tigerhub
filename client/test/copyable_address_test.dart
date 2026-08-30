/// Per line address copying.
///
/// The whole point is that web order forms want street, city, state and ZIP in
/// separate fields, so copying the block as one string means picking it apart
/// by hand every time. A copy that silently puts the wrong text on the
/// clipboard is invisible until someone pastes a ZIP into a street field, so
/// the clipboard contents are asserted rather than the tap being assumed to
/// work.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/copyable_address.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // RIT's mail is zone based: line two is your building and room, and the
  // street belongs to the post office (CLAUDE.md 7.9).
  const lines = [
    'Cole Wisniewski',
    'Peterson 1234',
    '43 Greenleaf Court',
    'Rochester NY 14623',
  ];

  late List<MethodCall> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  String? lastCopied() =>
      clipboard.isEmpty ? null : clipboard.last.arguments['text'] as String?;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: Center(child: SizedBox(width: 420, child: CopyableAddress(lines: lines))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('every line renders', (tester) async {
    await pump(tester);
    for (final line in lines) {
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('tapping one line copies only that line', (tester) async {
    await pump(tester);

    await tester.tap(find.text('43 Greenleaf Court'));
    await tester.pump();

    expect(lastCopied(), '43 Greenleaf Court',
        reason: 'a form field wants the street on its own, not the block');
    expect(lastCopied(), isNot(contains('Rochester')));
  });

  testWidgets('each line is separately reachable', (tester) async {
    await pump(tester);

    for (final line in lines) {
      await tester.tap(find.text(line));
      await tester.pump();
      expect(lastCopied(), line);
    }
    expect(clipboard.length, lines.length);
  });

  testWidgets('copy all takes the whole block, newline separated', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Copy all'));
    await tester.pump();

    expect(lastCopied(), lines.join('\n'));
  });

  testWidgets('confirms the copy, then goes back to resting', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.tap(find.text('Copy all'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget,
        reason: 'a copy with no feedback leaves you tapping twice');

    // The confirmation clears itself rather than sticking around.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Copy all'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('only the copied line shows its tick', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Peterson 1234'));
    await tester.pump();

    // One tick on the copied row. Copy-all is showing its own copy icon.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('a trailing widget sits beside the copy all button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: CopyableAddress(lines: lines, trailing: Text('unverified')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('unverified'), findsOneWidget);
  });
}
