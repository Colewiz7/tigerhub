import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/config.dart';
import 'package:tigerhub/services/frame_monitor.dart';

void main() {
  final monitor = FrameMonitor.instance;

  Widget list() => MaterialApp(
    home: Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) => monitor.onScroll(n, 2),
        child: ListView(
          children: [
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < 20; i++) SizedBox(width: 100, child: Text('chip $i'))],
              ),
            ),
            for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
          ],
        ),
      ),
    ),
  );

  void frameNow() =>
      monitor.stats.recordFrame(atUs: monitor.nowUs, buildUs: 1000, rasterUs: 1000);

  setUp(monitor.stats.reset);

  testWidgets('the list scrolling opens a scroll window', (tester) async {
    await tester.pumpWidget(list());
    final g = await tester.startGesture(tester.getCenter(find.text('row 3')));
    await g.moveBy(const Offset(0, -80));
    await tester.pump();
    frameNow();
    expect(monitor.stats.scrollSummary(2).frames, 1);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a horizontal chip row scroll does not', (tester) async {
    await tester.pumpWidget(list());
    final g = await tester.startGesture(tester.getCenter(find.text('chip 2')));
    await g.moveBy(const Offset(-120, 0));
    await tester.pump();
    frameNow();
    expect(monitor.stats.scrollSummary(2).frames, 0);
    await g.up();
    await tester.pumpAndSettle();
    frameNow();
    expect(monitor.stats.scrollSummary(2).frames, 0);
  });

  test('the shown version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final name = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(AppConfig.buildVersion, name);
  });
}
