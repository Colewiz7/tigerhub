/// Feeds the engine's frame timings into [FrameStats].
///
/// Always on, release builds included, because the numbers that matter come
/// from a phone running the shipping build. The callback only copies two
/// integers per frame into a ring. Nothing here notifies a listener: the stats
/// screen reads on its own timer.
library;

import 'dart:developer' show Timeline;
import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'frame_stats.dart';

class FrameMonitor {
  FrameMonitor._();

  static final FrameMonitor instance = FrameMonitor._();

  final FrameStats stats = FrameStats();

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (var i = 0; i < timings.length; i++) {
      final t = timings[i];
      stats.recordFrame(
        atUs: t.timestampInMicroseconds(FramePhase.buildStart),
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
      );
    }
  }

  /// On the same clock as the frame timestamps.
  int get nowUs => Timeline.now;

  void tabSwitched(int tab) => stats.tabSwitched(tab, nowUs);
  void scrollStarted(int tab) => stats.scrollStarted(tab, nowUs);
  void scrollEnded() => stats.scrollEnded(nowUs);

  /// The stats screen is open: its own frames are not counted.
  void pause() => stats.paused(nowUs);
  void resume() => stats.resumed(nowUs);

  /// Marks a tab's own vertical scrolls, for a notification listener at the
  /// shell. Horizontal scrollables and ones nested in another scrollable
  /// (a chip row in a list) are not the tab scrolling. Never handles it.
  bool onScroll(ScrollNotification n, int tab) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      scrollStarted(tab);
    } else if (n is ScrollEndNotification) {
      scrollEnded();
    }
    return false;
  }
}
