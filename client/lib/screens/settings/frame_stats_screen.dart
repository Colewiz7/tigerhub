/// Frame stats: a hidden screen for reading how smooth the app runs.
///
/// Reached by tapping the version row in About five times. Release builds
/// have it too, since the numbers worth having come from a phone. It reads the
/// recorder once a second while open and on Reset, and never per frame.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../data/sources/rit_chefs.dart'
    show chefsDiagnostics, chefsDiagnosticsLines;
import '../../services/frame_monitor.dart';
import '../../services/frame_stats.dart';
import '../../theme/tokens.dart';
import '../../widgets/focus_ring.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/touch_target.dart';

class FrameStatsScreen extends StatefulWidget {
  const FrameStatsScreen({super.key, this.stats, this.device});

  /// A recorder to read instead of the app's own, for tests.
  final FrameStats? stats;

  /// The OS and refresh rate lines to show instead of reading them, for tests.
  final List<String>? device;

  @override
  State<FrameStatsScreen> createState() => _FrameStatsScreenState();
}

class _FrameStatsScreenState extends State<FrameStatsScreen> {
  Timer? _refresh;
  Timer? _copiedTimer;
  bool _copied = false;

  FrameStats get _stats => widget.stats ??FrameMonitor.instance.stats;

  @override
  void initState() {
    super.initState();
    // Reading the stats sorts the rings. Frames drawn while this screen is up
    // would be its own cost, so they are not counted.
    FrameMonitor.instance.pause();
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    FrameMonitor.instance.resume();
    _refresh?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  List<String> _header(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final display = View.of(context).display;
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    return [
      '${AppConfig.appName} ${AppConfig.buildVersion}',
      ...(widget.device ??
          [
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
            'Refresh ${display.refreshRate.toStringAsFixed(0)} Hz',
          ]),
      'Text scale ${scale.toStringAsFixed(2)}',
      'Build $mode',
    ];
  }

  void _reset() {
    _stats.reset();
    setState(() => _copied = false);
  }

  Future<void> _copy(BuildContext context) async {
    final text = [
      _stats.report(_header(context)),
      'Visiting chefs',
      ...chefsDiagnosticsLines(chefsDiagnostics.value),
      '',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final stats = _stats;
    final all = stats.summary();

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            Insets.phoneMargin,
            6,
            Insets.phoneMargin,
            24,
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _BackButton(onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 4),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Frame stats',
                      style: text.titleLarge?.copyWith(fontSize: 22),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.phoneCardGap),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Button(label: 'Reset', onTap: _reset),
                _Button(
                  label: _copied ? 'Copied' : 'Copy report',
                  onTap: () => _copy(context),
                ),
              ],
            ),
            const SizedBox(height: Insets.phoneCardGap),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _header(context))
                    Text(line, style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: Insets.phoneCardGap),
            _Card(
              title: 'All frames',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Metric('Frames', '${all.frames}'),
                  if (all.retained < all.frames)
                    _Metric('Percentiles over last', '${all.retained}'),
                  _Metric('Over 8.3 ms', '${all.over120}'),
                  _Metric('Over 16.7 ms', '${all.over60}'),
                  _Metric(
                    'Build p50 / p90 / p99',
                    _trio(all.buildP50, all.buildP90, all.buildP99),
                    stacked: true,
                  ),
                  _Metric(
                    'Raster p50 / p90 / p99',
                    _trio(all.rasterP50, all.rasterP90, all.rasterP99),
                    stacked: true,
                  ),
                  _Metric('Worst frame', _ms(all.worstUs)),
                ],
              ),
            ),
            const SizedBox(height: Insets.phoneCardGap),
            _Card(
              title: 'Tab switch, first 500 ms',
              child: _Buckets(
                summary: stats.tabSwitchSummary,
                tabs: stats.tabs,
              ),
            ),
            const SizedBox(height: Insets.phoneCardGap),
            _Card(
              title: 'Scroll',
              child: _Buckets(summary: stats.scrollSummary, tabs: stats.tabs),
            ),
            const SizedBox(height: Insets.phoneCardGap),
            // What rit.edu last returned, for a "Menus unavailable" seen on a
            // phone. Read on the one second refresh like everything above.
            _Card(
              title: 'Visiting chefs',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in chefsDiagnosticsLines(
                    chefsDiagnostics.value,
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: Insets.phoneRowGap,
                      ),
                      child: Text(line, style: text.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  static String _ms(int us) => FrameStats.ms(us);

  static String _trio(int a, int b, int c) {
    String one(int us) => (us / 1000).toStringAsFixed(1);
    return '${one(a)} / ${one(b)} / ${one(c)} ms';
  }
}

class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.phoneCardPadding),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: Insets.phoneRowGap * 2),
          ],
          child,
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.stacked = false});

  final String label;
  final String value;

  /// Value under the label, for a long value.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // Large text leaves no room beside the label.
    final stack = stacked || MediaQuery.textScalerOf(context).scale(10) >= 15;
    final labelText = Text(label, style: text.bodyMedium?.copyWith(color: muted));
    return Semantics(
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.phoneRowGap),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [labelText, Text(value, style: text.bodyMedium)],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: 10),
                    Text(value, style: text.bodyMedium),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One line per tab: the worst frame and the p99 inside the bucket.
class _Buckets extends StatelessWidget {
  const _Buckets({required this.summary, required this.tabs});

  final FrameSummary Function(int tab) summary;
  final int tabs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tabs; i++)
          _Bucket(name: frameTabNames[i], summary: summary(i)),
      ],
    );
  }
}

class _Bucket extends StatelessWidget {
  const _Bucket({required this.name, required this.summary});

  final String name;
  final FrameSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final detail =
        'Worst ${FrameStats.ms(summary.worstUs)}, p99 ${FrameStats.ms(summary.totalP99)}, '
        '${summary.frames} frames'
        '${summary.retained < summary.frames ? ', p99 of last ${summary.retained}' : ''}';
    return Semantics(
      label: '$name, $detail',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.phoneRowGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: text.bodyMedium),
              Text(detail, style: text.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TouchTarget(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Back',
        child: FocusRing(
          radius: 20,
          builder: (onFocusChange) => InkWell(
            onTap: onTap,
            onFocusChange: onFocusChange,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ExcludeSemantics(
                child: Icon(
                  AppIconKind.back.of(context),
                  size: 24,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill button with a 48pt hit area.
class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: FocusRing(
        radius: 24,
        builder: (onFocusChange) => Material(
          color: scheme.surfaceContainerHigh,
          shape: Shapes.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onFocusChange: onFocusChange,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TouchTarget.size,
                minWidth: TouchTarget.size,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  widthFactor: 1,
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
