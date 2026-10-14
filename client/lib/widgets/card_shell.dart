/// Card chrome.
///
/// Surfaces nest by container level rather than by shadow: the card sits on
/// surfaceContainerLow, and anything nested inside it steps one level lighter.
/// Elevation is zero everywhere.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/api.dart';
import '../theme/tokens.dart';
import 'freshness.dart';
import 'glyph.dart';

/// Width of the edit controls row: handle, Inspect and Remove at 32 each with
/// 6 between. The header layout depends on it.
const double editControlsWidth = 32 * 3 + 6 * 2;

/// Gap between the title column, the hero and the edit controls.
const double _headerGap = 10;

/// Title width at which the edit controls still sit beside the title and hero.
/// Narrower than this they drop under the title when the band has room.
const double _asideTitleWidth = 96;

/// The least a title may keep beside the controls before the hero scales down.
const double _titleFloor = 48;

/// Gap between the title and the controls when they sit under it.
const double _belowGap = 6;

class CardShell extends StatelessWidget {
  const CardShell({
    super.key,
    required this.title,
    required this.child,
    this.state = DataState.ok,
    this.fetchedAt,
    this.hero,
    this.dragHandle,
    this.glyph,
  });

  final String title;

  /// Section identity, per `docs/glyph-adoption-spec.md`. Only cards the spec
  /// names carry one; the rest show the title alone rather than reaching for
  /// a Material icon that means nothing.
  final GlyphKind? glyph;
  final Widget child;
  final DataState state;
  final DateTime? fetchedAt;

  /// The single most important thing on this card, shown beside the title so
  /// it costs no vertical room from the list underneath.
  final Widget? hero;

  /// The edit mode controls (drag handle, Inspect, Remove), null outside edit
  /// mode. They take their own space in the header, never an overlay.
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);

    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      borderRadius: Shapes.card,
      child: Padding(
        padding: const EdgeInsets.all(Insets.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Every slot keeps its place in both modes, so toggling edit
            // mode never rebuilds the hero and replays its entrance.
            _CardHeader(
              hasHero: hero != null,
              editing: dragHandle != null,
              title: _CardTitle(title: title, glyph: glyph),
              freshness: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: FreshnessLine(state: state, fetchedAt: fetchedAt),
              ),
              hero: hero == null
                  ? const SizedBox.shrink()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: hero!,
                    ),
              controls: dragHandle ?? const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(state == DataState.priming),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The glyph and title. Given a finite height it keeps only the lines that fit
/// and ellipsizes past them; unbounded, it wraps freely. The ellipsis is only
/// visual: the Text still holds the full title.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.glyph});

  final String title;
  final GlyphKind? glyph;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    return LayoutBuilder(
      builder: (context, box) {
        int? lines;
        if (box.maxHeight.isFinite) {
          final painter = TextPainter(
            text: TextSpan(
              text: 'A',
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final lineHeight = painter.height;
          painter.dispose();
          lines = math.max(1, ((box.maxHeight + 0.5) / lineHeight).floor());
        }
        return Row(
          children: [
            if (glyph != null) ...[
              Glyph(glyph!, size: 22),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                title,
                style: style,
                maxLines: lines,
                overflow: lines == null
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The card header: title and freshness on the left, the hero on the right,
/// and in edit mode the controls.
///
/// The header's height is always the one it has outside edit mode: the taller
/// of the title column laid out in the room the hero leaves, and the hero. Edit
/// mode only decides where things go inside that band. The controls sit beside
/// the hero, with the title ellipsizing to the lines it already had; when that
/// leaves the title too little room they drop under the title if the band has
/// the height, and only as a last resort does a hero scale down to make room.
/// A card therefore never grows or shrinks, and the gap after it never moves,
/// whatever the hero or the text size.
///
/// Children, in order: title, freshness, hero, controls. Absent ones are
/// zero-size placeholders so the slots keep their identity.
class _CardHeader extends MultiChildRenderObjectWidget {
  _CardHeader({
    required this.hasHero,
    required this.editing,
    required Widget title,
    required Widget freshness,
    required Widget hero,
    required Widget controls,
  }) : super(children: [title, freshness, hero, controls]);

  final bool hasHero;
  final bool editing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardHeader(hasHero: hasHero, editing: editing);

  @override
  void updateRenderObject(BuildContext context, _RenderCardHeader renderObject) {
    renderObject
      ..hasHero = hasHero
      ..editing = editing;
  }
}

class _RenderCardHeader extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderCardHeader({required bool hasHero, required bool editing}) {
    _hasHero = hasHero;
    _editing = editing;
  }

  late bool _hasHero;
  bool get hasHero => _hasHero;
  set hasHero(bool value) {
    if (value == _hasHero) return;
    _hasHero = value;
    markNeedsLayout();
  }

  late bool _editing;
  bool get editing => _editing;
  set editing(bool value) {
    if (value == _editing) return;
    _editing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  static void _place(RenderBox child, double x, double y) {
    (child.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      x,
      y,
    );
  }

  @override
  void performLayout() {
    final title = firstChild!;
    final freshness = childAfter(title)!;
    final hero = childAfter(freshness)!;
    final controls = childAfter(hero)!;
    final maxW = constraints.maxWidth;

    Size layoutHero(BoxConstraints c) {
      hero.layout(c, parentUsesSize: true);
      return hero.size;
    }

    // Outside edit mode: the hero at its natural size, the title column in the
    // rest. This measurement sets the band in both modes.
    final heroNatural = layoutHero(const BoxConstraints());
    final heroGap = hasHero ? _headerGap : 0.0;
    final normalW = math.max(0.0, maxW - heroNatural.width - heroGap);
    title.layout(BoxConstraints(maxWidth: normalW), parentUsesSize: true);
    freshness.layout(BoxConstraints(maxWidth: normalW), parentUsesSize: true);
    final titleH = title.size.height;
    final freshH = freshness.size.height;
    final leftH = titleH + freshH;
    final band = math.max(leftH, heroNatural.height);
    size = constraints.constrain(Size(maxW, band));

    var heroX = maxW - heroNatural.width;
    _place(hero, heroX, (band - heroNatural.height) / 2);

    if (!editing) {
      _place(title, 0, (band - leftH) / 2);
      _place(freshness, 0, (band - leftH) / 2 + titleH);
      controls.layout(BoxConstraints.tight(Size.zero));
      _place(controls, 0, 0);
      return;
    }

    controls.layout(const BoxConstraints(), parentUsesSize: true);
    final cw = controls.size.width;
    final ch = controls.size.height;
    final asideRoom = maxW - heroNatural.width - heroGap - _headerGap - cw;
    final canGoBelow = cw <= normalW && leftH + _belowGap + ch <= band;

    if (asideRoom < _asideTitleWidth && canGoBelow) {
      // The title keeps its normal layout; the controls take the height the
      // hero's band leaves under it.
      final top = (band - (leftH + _belowGap + ch)) / 2;
      _place(title, 0, top);
      _place(freshness, 0, top + titleH);
      _place(controls, 0, top + leftH + _belowGap);
      return;
    }

    // Beside the hero. The hero keeps its size unless the title would be left
    // with less than the floor, and then it scales down rather than hide.
    var heroW = heroNatural.width;
    if (hasHero) {
      final cap = math.max(0.0, maxW - heroGap - _headerGap - cw - _titleFloor);
      if (heroW > cap) heroW = layoutHero(BoxConstraints(maxWidth: cap)).width;
    }
    final titleW = math.max(0.0, maxW - heroW - heroGap - _headerGap - cw);
    // The normal height as the ceiling keeps the normal line count.
    title.layout(
      BoxConstraints(maxWidth: titleW, maxHeight: titleH),
      parentUsesSize: true,
    );
    freshness.layout(BoxConstraints(maxWidth: titleW), parentUsesSize: true);
    final top = (band - (title.size.height + freshness.size.height)) / 2;
    _place(title, 0, top);
    _place(freshness, 0, top + title.size.height);
    final controlsX = maxW - cw;
    _place(controls, controlsX, (band - ch) / 2);
    heroX = hasHero ? controlsX - _headerGap - hero.size.width : 0;
    _place(hero, heroX, (band - hero.size.height) / 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A row inside a card. Separation comes from spacing, not from rules.
class RuledRow extends StatelessWidget {
  const RuledRow({super.key, required this.child, this.last = false});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: child);
}
