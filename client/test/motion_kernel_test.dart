import 'dart:convert';
import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/motion/gesture.dart';

void main() {
  final vectors = jsonDecode(File('test/fixtures/motion-vectors.json').readAsStringSync()) as Map<String, dynamic>;
  List<Map<String, dynamic>> cases(String kind) => (vectors[kind] as List).cast<Map<String, dynamic>>();
  double n(Object? v) => (v as num).toDouble();

  SpringDescription spring(num seconds, num bounce) => SpringDescription.withDurationAndBounce(duration: Duration(milliseconds: (seconds * 1000).round()), bounce: n(bounce));

  test('flutter springs match every spring vector', () {
    for (final c in cases('spring')) {
      final sim = SpringSimulation(spring(c['duration'], c['bounce']), n(c['from']), n(c['to']), n(c['v0']));
      final t = n(c['t']);
      expect(sim.x(t), closeTo(n(c['x']), 0.001), reason: '$c');
      expect(sim.dx(t), closeTo(n(c['v']), 0.001), reason: '$c');
    }
  });

  test('rubberband, project and decay match their vectors', () {
    for (final c in cases('rubberband')) {
      expect(rubberband(n(c['x']), n(c['d']), n(c['c'])), closeTo(n(c['out']), 0.001), reason: '$c');
    }
    for (final c in cases('project')) {
      expect(project(n(c['v']), n(c['rate'])), closeTo(n(c['out']), 0.001), reason: '$c');
    }
    for (final c in cases('decay')) {
      expect(decay(n(c['v']), n(c['rate']), n(c['t'])), closeTo(n(c['dx']), 0.001), reason: '$c');
    }
  });

  test('retargeting keeps the velocity', () {
    final first = SpringSimulation(spring(0.5, 0), 0, 100, 800);
    final x = first.x(0.08);
    final v = first.dx(0.08);
    final second = SpringSimulation(spring(0.5, 0), x, 40, v);
    expect(second.x(0), closeTo(x, 1e-9));
    expect(second.dx(0), closeTo(v, 1e-9));
  });

  testWidgets('60 and 120 hz trace the same curve', (tester) async {
    Future<List<double>> trace(int hz) async {
      final controller = AnimationController.unbounded(vsync: const TestVSync());
      final seen = <double>[];
      controller.animateWith(settle(0, 120, 2400, const Duration(milliseconds: 180)));
      await tester.pump();
      for (var frame = 0; frame < hz / 2; frame++) {
        await tester.pump(Duration(microseconds: 1000000 ~/ hz));
        if (frame % (hz ~/ 60) == hz ~/ 60 - 1) seen.add(controller.value);
      }
      controller.dispose();
      return seen;
    }

    final at60 = await trace(60);
    final at120 = await trace(120);
    expect(at60, hasLength(30));
    for (var i = 0; i < at60.length; i++) {
      expect(at120[i], closeTo(at60[i], 1e-6));
    }
  });

  test('a clamped release never passes the target', () {
    for (final duration in const [180, 240]) {
      for (final distance in const [4.0, 40.0, 400.0, -40.0]) {
        for (var speed = 0.0; speed <= 20000; speed += 250) {
          final velocity = distance.sign * speed;
          final sim = settle(0, distance, velocity, Duration(milliseconds: duration));
          for (var frame = 0; frame <= 240; frame++) {
            final x = sim.x(frame / 120);
            expect(distance > 0 ? x <= distance + 1e-9 : x >= distance - 1e-9, isTrue, reason: 'd $distance v $velocity t ${frame / 120}');
          }
        }
      }
    }
  });

  test('settle stops within half a pixel at under 5 px/s', () {
    final sim = settle(0, 120, 2400, const Duration(milliseconds: 180));
    expect(sim.tolerance.distance, 0.5);
    expect(sim.tolerance.velocity, 5);
    var done = 0.0;
    for (var frame = 0; frame <= 240; frame++) {
      final t = frame / 240;
      final resting = (sim.x(t) - 120).abs() < 0.5 && sim.dx(t).abs() < 5;
      expect(sim.isDone(t), resting, reason: 't $t');
      if (resting && done == 0) done = t;
    }
    expect(done, greaterThan(0));
    expect(done, lessThan(0.5), reason: 'not held for the default 0.001 px');
  });

  test('release velocity reads the last 100 ms, zero after a rest', () {
    final tracker = ReleaseTracker();
    for (var t = 0; t <= 300; t += 10) {
      // slow then fast, only the fast part counts
      tracker.add(t < 200 ? t * 0.1 : 20 + (t - 200) * 2.0, t.toDouble());
    }
    expect(tracker.velocity(300), closeTo(2000, 1e-9));
    expect(tracker.velocity(351), 0, reason: 'rested before lifting');
    tracker.clear();
    tracker.add(0, 5);
    tracker.add(10, 5);
    expect(tracker.velocity(5), 0);
  });

  test('without the clamp a fast release overshoots', () {
    final sim = SpringSimulation(spring(0.18, 0), 0, 40, 2 * 2 * 3.141592653589793 / 0.18 * 40);
    final peak = [for (var f = 0; f <= 120; f++) sim.x(f / 240)].reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(40));
  });
}
