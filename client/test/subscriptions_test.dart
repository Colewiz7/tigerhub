/// Subscriptions must not outlive the widget that made them.
///
/// This is the bug behind "glitches out when switching pages". Every screen
/// reads its data from a stream that emits twice, once from cache and once from
/// the refresh behind it, and fourteen call sites did that without keeping the
/// subscription. Two things then went wrong at once:
///
///   the refresh ticker re-subscribed four streams every two minutes, so the
///   count grew for as long as the app stayed open
///
///   opening the Campus tab subscribed six more, and leaving did not cancel
///   them, so every visit added another set
///
/// The leak was not the symptom. Stale subscriptions kept delivering, so a
/// result from a previous visit could land after a newer one and overwrite it,
/// and the screen showed the wrong thing or flickered between two.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/services/subscriptions.dart';

void main() {
  test('cancelling stops delivery, so a stale result cannot land late', () async {
    final controller = StreamController<int>.broadcast();
    final seen = <int>[];
    final bag = Subscriptions()
      ..add(controller.stream.listen(seen.add));

    controller.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1]);

    bag.cancelAll();
    controller.add(2);
    await Future<void>.delayed(Duration.zero);

    expect(seen, [1],
        reason: 'a cancelled subscription still delivered, which is how an '
            'old page overwrote the current one');
    await controller.close();
  });

  test('re-subscribing replaces rather than stacks', () async {
    final controller = StreamController<int>.broadcast();
    var deliveries = 0;
    final bag = Subscriptions();

    // Five refresh ticks, the way the two minute ticker would.
    for (var tick = 0; tick < 5; tick++) {
      bag.cancelAll();
      bag.add(controller.stream.listen((_) => deliveries++));
    }

    expect(bag.length, 1, reason: 'five ticks left five live subscriptions');

    controller.add(1);
    await Future<void>.delayed(Duration.zero);

    expect(deliveries, 1,
        reason: 'one event was handled once per stacked subscription, which is '
            'setState called N times for a single update');
    await controller.close();
  });

  test('dispose cancels everything held', () async {
    final a = StreamController<int>.broadcast();
    final b = StreamController<int>.broadcast();
    final seen = <String>[];

    final bag = Subscriptions()
      ..add(a.stream.listen((_) => seen.add('a')))
      ..add(b.stream.listen((_) => seen.add('b')));

    expect(bag.length, 2);
    bag.dispose();

    a.add(1);
    b.add(1);
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty, reason: 'a disposed screen kept receiving updates');
    expect(bag.length, 0);
    await a.close();
    await b.close();
  });

  test('no widget listens to a stream without holding it', () {
    // The original bug was fourteen call sites and no cancellation. Fixing
    // them is only half the job: the fifteenth is the one that reintroduces
    // it, and the symptom is subtle enough that nobody links it back.
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // The data layer has no widgets, and dynamic_theme holds its own.
      if (file.path.startsWith('lib/data/')) continue;
      if (file.path.endsWith('dynamic_theme.dart')) continue;

      final source = file.readAsStringSync();
      if (!source.contains('.listen(')) continue;

      final held = source.contains('_subscriptions.add(') ||
          source.contains('..add(');
      if (!held) offenders.add(file.path);
    }

    expect(offenders, isEmpty,
        reason: 'these subscribe without keeping the subscription, so it '
            'outlives the widget and delivers into a dead screen: $offenders');
  });

  test('is safe to cancel when empty, and twice', () {
    final bag = Subscriptions();
    expect(bag.cancelAll, returnsNormally);
    bag.dispose();
    expect(bag.dispose, returnsNormally);
  });
}
