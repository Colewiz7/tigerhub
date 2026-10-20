/// Frame timing statistics, as plain Dart.
///
/// The engine hands over a build and a raster duration per frame. This keeps
/// the most recent ones in fixed rings, so recording a frame allocates nothing,
/// and answers the questions the hidden stats screen asks: how many frames were
/// slow, and what the percentiles are overall and inside two kinds of window,
/// the first 500ms after a tab switch and the time a scroll is active.
///
/// Time is passed in as microseconds so the tests can fake it. A frame belongs
/// to a window by its own start time, not by when the engine reported it, which
/// can be several frames late.
library;

import 'dart:typed_data';

/// Tab names in the order the shell lists them.
const List<String> frameTabNames = ['Today', 'Dining', 'Events', 'Map', 'Campus'];

/// What a frame has to beat to fit a 120Hz and a 60Hz display.
const int frameBudget120Us = 8333;
const int frameBudget60Us = 16667;

/// How long after a tab switch its frames count toward the tab switch bucket.
const int tabSwitchWindowUs = 500000;

/// Switch and scroll events kept for attributing late reported frames.
const int _eventCapacity = 256;

/// Numbers for one set of frames. All durations are microseconds.
class FrameSummary {
  const FrameSummary({
    required this.frames,
    required this.over120,
    required this.over60,
    required this.worstUs,
    required this.buildP50,
    required this.buildP90,
    required this.buildP99,
    required this.rasterP50,
    required this.rasterP90,
    required this.rasterP99,
    required this.totalP99,
  });

  static const empty = FrameSummary(
    frames: 0,
    over120: 0,
    over60: 0,
    worstUs: 0,
    buildP50: 0,
    buildP90: 0,
    buildP99: 0,
    rasterP50: 0,
    rasterP90: 0,
    rasterP99: 0,
    totalP99: 0,
  );

  /// Frames recorded since the last reset, including any the ring has dropped.
  final int frames;

  /// Frames whose build plus raster time beat [frameBudget120Us].
  final int over120;

  /// Frames whose build plus raster time beat [frameBudget60Us].
  final int over60;

  /// The slowest frame's build plus raster time since the last reset.
  final int worstUs;

  final int buildP50;
  final int buildP90;
  final int buildP99;
  final int rasterP50;
  final int rasterP90;
  final int rasterP99;
  final int totalP99;
}

/// The value at percentile [p] (0 to 1) of an ascending list, nearest rank.
/// Zero for an empty list.
int percentile(Int32List sorted, int length, double p) {
  if (length == 0) return 0;
  final rank = (p * length).ceil().clamp(1, length);
  return sorted[rank - 1];
}

/// A fixed size ring of frames, with running counts that survive wrapping.
class _Ring {
  _Ring(int capacity)
    : _build = Int32List(capacity),
      _raster = Int32List(capacity);

  final Int32List _build;
  final Int32List _raster;
  int _next = 0;
  int _length = 0;

  int frames = 0;
  int over120 = 0;
  int over60 = 0;
  int worst = 0;

  void add(int buildUs, int rasterUs) {
    _build[_next] = buildUs;
    _raster[_next] = rasterUs;
    _next = (_next + 1) % _build.length;
    if (_length < _build.length) _length++;
    frames++;
    final total = buildUs + rasterUs;
    if (total > frameBudget120Us) over120++;
    if (total > frameBudget60Us) over60++;
    if (total > worst) worst = total;
  }

  void clear() {
    _next = 0;
    _length = 0;
    frames = 0;
    over120 = 0;
    over60 = 0;
    worst = 0;
  }

  FrameSummary summary() {
    if (_length == 0) return FrameSummary.empty;
    final build = Int32List.sublistView(_build, 0, _length);
    final raster = Int32List.sublistView(_raster, 0, _length);
    final total = Int32List(_length);
    for (var i = 0; i < _length; i++) {
      total[i] = _build[i] + _raster[i];
    }
    // Copies, so the ring keeps its arrival order.
    final b = Int32List.fromList(build)..sort();
    final r = Int32List.fromList(raster)..sort();
    total.sort();
    return FrameSummary(
      frames: frames,
      over120: over120,
      over60: over60,
      worstUs: worst,
      buildP50: percentile(b, _length, 0.5),
      buildP90: percentile(b, _length, 0.9),
      buildP99: percentile(b, _length, 0.99),
      rasterP50: percentile(r, _length, 0.5),
      rasterP90: percentile(r, _length, 0.9),
      rasterP99: percentile(r, _length, 0.99),
      totalP99: percentile(total, _length, 0.99),
    );
  }
}

class _Switch {
  const _Switch(this.tab, this.atUs);
  final int tab;
  final int atUs;
}

class _Scroll {
  _Scroll(this.tab, this.startUs);
  final int tab;
  final int startUs;

  /// Null while the scroll is still active.
  int? endUs;
}

class FrameStats {
  FrameStats({int capacity = 20000, int bucketCapacity = 4000, int tabs = 5})
    : _all = _Ring(capacity),
      _switchRings = [for (var i = 0; i < tabs; i++) _Ring(bucketCapacity)],
      _scrollRings = [for (var i = 0; i < tabs; i++) _Ring(bucketCapacity)];

  final _Ring _all;
  final List<_Ring> _switchRings;
  final List<_Ring> _scrollRings;

  final List<_Switch> _switches = [];
  final List<_Scroll> _scrolls = [];
  int _scrollDepth = 0;

  int get tabs => _switchRings.length;

  /// The shell changed to [tab] at [atUs].
  ///
  /// A scroll still open is closed here: its end notification belongs to a
  /// tab that is no longer shown and may never arrive.
  void tabSwitched(int tab, int atUs) {
    _closeScroll(atUs);
    _scrollDepth = 0;
    if (_switches.length == _eventCapacity) _switches.removeAt(0);
    _switches.add(_Switch(tab, atUs));
  }

  /// A scroll began on [tab]. Nested scrollables count as one scroll.
  void scrollStarted(int tab, int atUs) {
    if (_scrollDepth == 0) {
      if (_scrolls.length == _eventCapacity) _scrolls.removeAt(0);
      _scrolls.add(_Scroll(tab, atUs));
    }
    _scrollDepth++;
  }

  void scrollEnded(int atUs) {
    if (_scrollDepth == 0) return;
    _scrollDepth--;
    if (_scrollDepth == 0) _closeScroll(atUs);
  }

  void _closeScroll(int atUs) {
    if (_scrolls.isEmpty) return;
    final last = _scrolls.last;
    last.endUs ??= atUs;
  }

  /// Records one frame that started at [atUs].
  void recordFrame({
    required int atUs,
    required int buildUs,
    required int rasterUs,
  }) {
    _all.add(buildUs, rasterUs);

    // Latest switch at or before the frame, if the frame is inside its window.
    for (var i = _switches.length - 1; i >= 0; i--) {
      final s = _switches[i];
      if (s.atUs > atUs) continue;
      if (atUs - s.atUs < tabSwitchWindowUs && s.tab < tabs) {
        _switchRings[s.tab].add(buildUs, rasterUs);
      }
      break;
    }

    for (var i = _scrolls.length - 1; i >= 0; i--) {
      final s = _scrolls[i];
      if (s.startUs > atUs) continue;
      final end = s.endUs;
      if ((end == null || atUs < end) && s.tab < tabs) {
        _scrollRings[s.tab].add(buildUs, rasterUs);
      }
      break;
    }
  }

  void reset() {
    _all.clear();
    for (final ring in _switchRings) {
      ring.clear();
    }
    for (final ring in _scrollRings) {
      ring.clear();
    }
    // Windows already opened keep applying to frames that arrive later; only
    // the history that can no longer matter goes.
    if (_switches.length > 1) _switches.removeRange(0, _switches.length - 1);
    if (_scrolls.length > 1 && _scrolls.last.endUs != null) {
      _scrolls.removeRange(0, _scrolls.length - 1);
    }
  }

  FrameSummary summary() => _all.summary();
  FrameSummary tabSwitchSummary(int tab) => _switchRings[tab].summary();
  FrameSummary scrollSummary(int tab) => _scrollRings[tab].summary();

  /// The plain text report, for the clipboard. [header] lines come first.
  String report(List<String> header) {
    final out = StringBuffer();
    for (final line in header) {
      out.writeln(line);
    }
    out.writeln();
    _writeSummary(out, 'All frames', summary());
    out.writeln();
    out.writeln('Tab switch (first 500 ms)');
    for (var i = 0; i < tabs; i++) {
      _writeLine(out, frameTabNames[i], tabSwitchSummary(i));
    }
    out.writeln();
    out.writeln('Scroll');
    for (var i = 0; i < tabs; i++) {
      _writeLine(out, frameTabNames[i], scrollSummary(i));
    }
    return out.toString();
  }

  static void _writeSummary(StringBuffer out, String title, FrameSummary s) {
    out.writeln(title);
    out.writeln('frames ${s.frames}');
    out.writeln('over 8.3 ms ${s.over120}');
    out.writeln('over 16.7 ms ${s.over60}');
    out.writeln('build p50 ${ms(s.buildP50)} p90 ${ms(s.buildP90)} p99 ${ms(s.buildP99)}');
    out.writeln('raster p50 ${ms(s.rasterP50)} p90 ${ms(s.rasterP90)} p99 ${ms(s.rasterP99)}');
    out.writeln('worst ${ms(s.worstUs)}');
  }

  static void _writeLine(StringBuffer out, String name, FrameSummary s) {
    out.writeln(
      '$name: frames ${s.frames}, worst ${ms(s.worstUs)}, p99 ${ms(s.totalP99)}, '
      'over 8.3 ${s.over120}, over 16.7 ${s.over60}',
    );
  }

  /// Microseconds as milliseconds with one decimal.
  static String ms(int us) => '${(us / 1000).toStringAsFixed(1)} ms';
}
