/// Phone mode: env parsing, an exact centered phone box, text scale, and a no-op when off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/phone_frame.dart';

void main() {
  group('parse', () {
    PhoneMode? parse(Map<String, String> env, {bool release = false}) => PhoneMode.parse(env, release: release);

    test('off when absent, empty, 0 or false', () {
      expect(parse({}), isNull);
      expect(parse({'TIGERHUB_PHONE': ''}), isNull);
      expect(parse({'TIGERHUB_PHONE': '0'}), isNull);
      expect(parse({'TIGERHUB_PHONE': 'false'}), isNull);
    });

    test('1 means the default 390x844', () {
      expect(parse({'TIGERHUB_PHONE': '1'})!.size, const Size(390, 844));
    });

    test('WxH picks a size', () {
      expect(parse({'TIGERHUB_PHONE': '430x932'})!.size, const Size(430, 932));
      expect(parse({'TIGERHUB_PHONE': '411X914'})!.size, const Size(411, 914));
    });

    test('a malformed or absurd size falls back to the default', () {
      for (final bad in ['abc', '430', '430x', 'x932', '10x10', '9999x9999', '430x932x1', '-430x932']) {
        expect(parse({'TIGERHUB_PHONE': bad})!.size, const Size(390, 844), reason: bad);
      }
    });

    test('text scale is read when sane and ignored otherwise', () {
      expect(parse({'TIGERHUB_PHONE': '1', 'TIGERHUB_TEXT_SCALE': '2.0'})!.textScale, 2.0);
      for (final bad in ['abc', '0', '-1', '9', '']) {
        expect(parse({'TIGERHUB_PHONE': '1', 'TIGERHUB_TEXT_SCALE': bad})!.textScale, isNull, reason: bad);
      }
    });

    test('text scale alone does not turn the mode on', () {
      expect(parse({'TIGERHUB_TEXT_SCALE': '2.0'}), isNull);
    });

    test('never on in a release build', () {
      expect(parse({'TIGERHUB_PHONE': '1'}, release: true), isNull);
    });
  });

  Widget app(PhoneMode? mode, Widget body) => MaterialApp(
    builder: phoneModeBuilder(mode),
    home: Scaffold(body: body),
  );

  Future<void> bigWindow(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1500, 1000);
    addTearDown(tester.view.reset);
  }

  testWidgets('yields exactly 390x844, centered, with matching MediaQuery', (tester) async {
    await bigWindow(tester);
    late Size seen;
    await tester.pumpWidget(
      app(
        const PhoneMode(),
        Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.expand(key: Key('page'));
          },
        ),
      ),
    );

    expect(seen, const Size(390, 844));
    final page = tester.getRect(find.byKey(const Key('page')));
    expect(page.size, const Size(390, 844));
    expect(page.center, const Offset(750, 500));
  });

  testWidgets('another size is honoured', (tester) async {
    await bigWindow(tester);
    await tester.pumpWidget(app(const PhoneMode(size: Size(430, 932)), const SizedBox.expand(key: Key('page'))));
    expect(tester.getSize(find.byKey(const Key('page'))), const Size(430, 932));
  });

  testWidgets('text scale override reaches the app', (tester) async {
    await bigWindow(tester);
    late TextScaler scaler;
    await tester.pumpWidget(
      app(
        const PhoneMode(textScale: 2.0),
        Builder(
          builder: (context) {
            scaler = MediaQuery.textScalerOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(scaler.scale(10), 20);
  });

  testWidgets('no text scale override keeps the system scale', (tester) async {
    await bigWindow(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    late TextScaler scaler;
    await tester.pumpWidget(
      app(
        const PhoneMode(),
        Builder(
          builder: (context) {
            scaler = MediaQuery.textScalerOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(scaler.scale(10), 15);
  });

  testWidgets('a window smaller than the phone scales it down without overflow', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(300, 500);
    addTearDown(tester.view.reset);
    late Size seen;
    await tester.pumpWidget(
      app(
        const PhoneMode(),
        Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.expand(key: Key('page'));
          },
        ),
      ),
    );
    expect(seen, const Size(390, 844));
    expect(tester.takeException(), isNull);
    final page = find.byKey(const Key('page'));
    expect(tester.getBottomRight(page).dx - tester.getTopLeft(page).dx, lessThanOrEqualTo(300));
    expect(tester.getBottomRight(page).dy - tester.getTopLeft(page).dy, lessThanOrEqualTo(500));
  });

  testWidgets('is a no-op when disabled', (tester) async {
    await bigWindow(tester);
    late Size seen;
    await tester.pumpWidget(
      app(
        null,
        Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.expand(key: Key('page'));
          },
        ),
      ),
    );

    expect(seen, const Size(1500, 1000));
    expect(tester.getSize(find.byKey(const Key('page'))), const Size(1500, 1000));
    expect(find.byType(PhoneFrame), findsNothing);
  });
}
