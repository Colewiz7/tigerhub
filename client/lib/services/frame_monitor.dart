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

import 'frame_stats.dart';

class FrameMonitor {
  FrameMonitor._();

  static final FrameMonitor instance = FrameMonitor._();

  final FrameStats stats = FrameStats();

  bool _started = false;

  /// While true, frames are dropped. The stats screen sets it so its own
  /// refresh work does not count.
  bool paused = false;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (paused) return;
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
}
