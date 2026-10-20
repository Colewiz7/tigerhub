import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/services/frame_stats.dart';

void main() {
  void frame(FrameStats s, int at, {int build = 1000, int raster = 1000}) =>
      s.recordFrame(atUs: at, buildUs: build, rasterUs: raster);

  group('percentile', () {
    test('empty list is zero', () {
      expect(percentile(Int32List(0), 0, 0.99), 0);
    });

    test('one value is every percentile', () {
      final one = Int32List.fromList([7]);
      expect(percentile(one, 1, 0.5), 7);
      expect(percentile(one, 1, 0.99), 7);
    });

    test('nearest rank on ten values', () {
      final v = Int32List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(percentile(v, 10, 0.5), 5);
      expect(percentile(v, 10, 0.9), 9);
      expect(percentile(v, 10, 0.99), 10);
    });

    test('ties give the tied value', () {
      final v = Int32List.fromList([4, 4, 4, 4, 9]);
      expect(percentile(v, 5, 0.5), 4);
      expect(percentile(v, 5, 0.8), 4);
      expect(percentile(v, 5, 0.9), 9);
    });
  });

  group('summary', () {
    test('empty has zeros', () {
      final s = FrameStats().summary();
      expect(s.frames, 0);
      expect(s.worstUs, 0);
      expect(s.buildP99, 0);
      expect(s.over120, 0);
    });

    test('one frame', () {
      final s = FrameStats();
      frame(s, 0, build: 3000, raster: 4000);
      final sum = s.summary();
      expect(sum.frames, 1);
      expect(sum.worstUs, 7000);
      expect(sum.buildP50, 3000);
      expect(sum.rasterP99, 4000);
      expect(sum.totalP99, 7000);
      expect(sum.over120, 0);
    });

    test('thresholds are on build plus raster and exclusive', () {
      final s = FrameStats();
      frame(s, 0, build: 4000, raster: 4333); // 8333, not over
      frame(s, 1, build: 4000, raster: 4334); // 8334, over 8.3
      frame(s, 2, build: 8000, raster: 8667); // 16667, over 8.3 only
      frame(s, 3, build: 8000, raster: 8668); // 16668, over both
      final sum = s.summary();
      expect(sum.over120, 3);
      expect(sum.over60, 1);
      expect(sum.worstUs, 16668);
    });

    test('percentiles separate build from raster', () {
      final s = FrameStats();
      for (var i = 1; i <= 100; i++) {
        frame(s, i, build: i * 10, raster: 5000 - i * 10);
      }
      final sum = s.summary();
      expect(sum.frames, 100);
      expect(sum.buildP50, 500);
      expect(sum.buildP90, 900);
      expect(sum.buildP99, 990);
      expect(sum.rasterP50, 4490);
      expect(sum.totalP99, 5000);
    });

    test('the ring keeps the newest frames but counts every frame', () {
      final s = FrameStats(capacity: 4);
      frame(s, 0, build: 9000, raster: 9000); // dropped from the ring
      for (var i = 1; i <= 4; i++) {
        frame(s, i, build: 1000, raster: 1000);
      }
      final sum = s.summary();
      expect(sum.frames, 5);
      expect(sum.buildP99, 1000);
      // The worst frame is kept even after its sample is gone.
      expect(sum.worstUs, 18000);
      expect(sum.over60, 1);
    });
  });

  group('tab switch bucket', () {
    test('frames in the first 500ms count, the boundary does not', () {
      final s = FrameStats();
      s.tabSwitched(2, 1000000);
      frame(s, 999999); // before the switch
      frame(s, 1000000); // at the switch
      frame(s, 1499999); // last microsecond inside
      frame(s, 1500000); // 500ms exactly, outside
      expect(s.tabSwitchSummary(2).frames, 2);
      expect(s.summary().frames, 4);
    });

    test('each tab has its own bucket', () {
      final s = FrameStats();
      s.tabSwitched(1, 0);
      frame(s, 10, build: 5000);
      s.tabSwitched(3, 100000);
      frame(s, 110000, build: 9000);
      expect(s.tabSwitchSummary(1).frames, 1);
      expect(s.tabSwitchSummary(1).worstUs, 6000);
      expect(s.tabSwitchSummary(3).frames, 1);
      expect(s.tabSwitchSummary(3).worstUs, 10000);
      expect(s.tabSwitchSummary(0).frames, 0);
    });

    test('a later switch takes over the window', () {
      final s = FrameStats();
      s.tabSwitched(0, 0);
      s.tabSwitched(4, 200000);
      frame(s, 250000);
      expect(s.tabSwitchSummary(0).frames, 0);
      expect(s.tabSwitchSummary(4).frames, 1);
    });

    test('frames reported late still land by their own time', () {
      final s = FrameStats();
      s.tabSwitched(1, 0);
      s.tabSwitched(2, 2000000);
      frame(s, 100000); // arrives after the second switch
      expect(s.tabSwitchSummary(1).frames, 1);
      expect(s.tabSwitchSummary(2).frames, 0);
    });

    test('frames before any switch are in no bucket', () {
      final s = FrameStats();
      frame(s, 5);
      for (var i = 0; i < s.tabs; i++) {
        expect(s.tabSwitchSummary(i).frames, 0);
        expect(s.scrollSummary(i).frames, 0);
      }
    });
  });

  group('scroll bucket', () {
    test('counts frames between start and end', () {
      final s = FrameStats();
      s.scrollStarted(1, 1000);
      frame(s, 999);
      frame(s, 1000);
      frame(s, 1999);
      s.scrollEnded(2000);
      frame(s, 2000);
      frame(s, 3000);
      expect(s.scrollSummary(1).frames, 2);
    });

    test('an active scroll counts frames reported before it ends', () {
      final s = FrameStats();
      s.scrollStarted(0, 0);
      frame(s, 50);
      frame(s, 10000000);
      expect(s.scrollSummary(0).frames, 2);
    });

    test('nested scrolls are one scroll', () {
      final s = FrameStats();
      s.scrollStarted(2, 0);
      s.scrollStarted(2, 10);
      s.scrollEnded(500);
      frame(s, 600); // outer scroll still active
      s.scrollEnded(1000);
      frame(s, 1100);
      expect(s.scrollSummary(2).frames, 1);
    });

    test('an end with no start does nothing', () {
      final s = FrameStats();
      s.scrollEnded(5);
      frame(s, 6);
      expect(s.scrollSummary(0).frames, 0);
    });

    test('two scrolls leave a gap between them', () {
      final s = FrameStats();
      s.scrollStarted(3, 0);
      s.scrollEnded(1000);
      s.scrollStarted(3, 5000);
      s.scrollEnded(6000);
      frame(s, 500);
      frame(s, 3000);
      frame(s, 5500);
      expect(s.scrollSummary(3).frames, 2);
    });

    test('switching tabs closes a scroll that never ended', () {
      final s = FrameStats();
      s.scrollStarted(1, 0);
      s.tabSwitched(2, 1000);
      frame(s, 2000);
      expect(s.scrollSummary(1).frames, 0);
      // A fresh scroll after the switch is counted on the new tab.
      s.scrollStarted(2, 3000);
      frame(s, 3500);
      expect(s.scrollSummary(2).frames, 1);
    });

    test('a frame can be in both a tab switch and a scroll', () {
      final s = FrameStats();
      s.tabSwitched(0, 0);
      s.scrollStarted(0, 100);
      frame(s, 200);
      expect(s.tabSwitchSummary(0).frames, 1);
      expect(s.scrollSummary(0).frames, 1);
      expect(s.summary().frames, 1);
    });
  });

  group('reset and report', () {
    test('reset empties every bucket', () {
      final s = FrameStats();
      s.tabSwitched(0, 0);
      s.scrollStarted(0, 0);
      frame(s, 10, build: 20000);
      s.reset();
      expect(s.summary().frames, 0);
      expect(s.summary().worstUs, 0);
      expect(s.tabSwitchSummary(0).frames, 0);
      expect(s.scrollSummary(0).frames, 0);
    });

    test('an open scroll keeps counting after a reset', () {
      final s = FrameStats();
      s.scrollStarted(1, 0);
      s.reset();
      frame(s, 10);
      expect(s.scrollSummary(1).frames, 1);
    });

    test('many events do not grow without bound', () {
      final s = FrameStats();
      for (var i = 0; i < 1000; i++) {
        s.tabSwitched(i % 5, i * 1000);
        s.scrollStarted(i % 5, i * 1000 + 1);
        s.scrollEnded(i * 1000 + 2);
      }
      frame(s, 999 * 1000 + 100);
      expect(s.tabSwitchSummary(999 % 5).frames, 1);
    });

    test('report has the header, every bucket and no em dash', () {
      final s = FrameStats();
      s.tabSwitched(3, 0);
      frame(s, 1, build: 12000, raster: 3000);
      final text = s.report(['TigerHub 1', 'Build release']);
      expect(text, startsWith('TigerHub 1\nBuild release\n'));
      expect(text, contains('frames 1'));
      expect(text, contains('worst 15.0 ms'));
      expect(text, contains('Map: frames 1, worst 15.0 ms'));
      for (final name in frameTabNames) {
        expect(text, contains('$name: frames'));
      }
      expect(text, isNot(contains('—')));
    });
  });
}
