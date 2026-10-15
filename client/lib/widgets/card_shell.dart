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

/// Height of the edit controls row: every control is 32 tall.
const double editControlsHeight = 32;

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
      borderRadius: Shapes.cardFor(context),
      child: Padding(
        padding: EdgeInsets.all(Insets.cardPaddingFor(context)),
        child: LayoutBuilder(
          builder: (context, box) => Column(
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
            // The header is 32 tall on phones, because the edit controls are,
            // so 8 here puts the content 56 from the card's top (16 + 32 + 8),
            // the same as a 28 header and a 12 gap would. Wider windows keep
            // the spec's 12.
            SizedBox(height: Insets.phone(context) ? 8 : 12),
            // In a fixed height cell the content takes what the header
            // leaves. On phones the card is as tall as its content, so there
            // is no height to divide and the content is laid out as it is.
            _FlexibleIfBounded(
              bounded: box.maxHeight.isFinite,
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
      ),
    );
  }
}

/// A Flexible when the column it sits in has a height to share, the child as
/// is when that height is unbounded (Flex asserts on a flex child there).
class _FlexibleIfBounded extends StatelessWidget {
  const _FlexibleIfBounded({required this.bounded, required this.child});

  final bool bounded;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      bounded ? Flexible(child: child) : child;
}

/// The glyph and title. The title wraps by whole words and is never cut: the
/// header gives it room by moving the controls (see [_CardHeader]), so a name
/// like "Visiting Chefs" or "Mailing Address" is always shown in full.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.glyph});

  final String title;
  final GlyphKind? glyph;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleLarge;
    // Phones: title 22, no tracking.
    final style = Insets.phone(context)
        ? base?.copyWith(fontSize: 22, letterSpacing: 0)
        : base;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (glyph != null) ...[
          SizedBox(width: 22, height: 22, child: Glyph(glyph!, size: 22)),
          const SizedBox(width: 9),
        ],
        Flexible(child: Text(title, style: style)),
      ],
    );
  }
}

/// The card header: title and freshness on the left, the hero on the right,
/// and in edit mode the controls.
///
/// The header has one height in both modes: the taller of what it needs
/// outside edit mode and what it needs inside it. Edit mode only decides where
/// things go inside that band, so toggling it never grows or shrinks a card or
/// moves the gap after it, whatever the hero or the text size.
///
/// The title wraps by whole words and is never cut. In edit mode the controls
/// sit beside the hero when the title column left of them still holds its
/// longest word; otherwise they take their own row under the title and hero.
/// A hero never scales down or hides.
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

    hero.layout(const BoxConstraints(), parentUsesSize: true);
    final heroW = hero.size.width;
    final heroH = hero.size.height;
    final heroGap = hasHero ? _headerGap : 0.0;

    /// Lays the title and freshness line out in [width]; returns their height.
    double layoutLeft(double width) {
      title.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      freshness.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      return title.size.height + freshness.size.height;
    }

    const cw = editControlsWidth;
    const ch = editControlsHeight;
    final longestWord = title.getMinIntrinsicWidth(double.infinity);

    // Outside edit mode the hero sits beside the title if the title keeps its
    // longest word there; otherwise it drops under the title ("stacked").
    final normalW = math.max(0.0, maxW - heroW - heroGap);
    final heroBeside = normalW >= longestWord;
    final topLeftH = layoutLeft(heroBeside ? normalW : maxW);
    final stackedHero = !heroBeside && hasHero;
    final normalBand = stackedHero
        ? topLeftH + _belowGap + heroH
        : math.max(topLeftH, heroH);

    // Inside edit mode the controls sit beside the hero when the title keeps
    // its longest word there ("aside"); else on a row under the title and hero
    // ("below"); else, with the hero already stacked, they share the hero's
    // row if both fit, or take their own. Both modes use the taller of the two
    // bands so toggling never moves what is below.
    final asideW = maxW - cw - _headerGap - heroW - heroGap;
    final sharesHeroRow = stackedHero && heroW + _headerGap + cw <= maxW;
    final belowBand = sharesHeroRow
        ? topLeftH + _belowGap + math.max(heroH, ch)
        : normalBand + _belowGap + ch;
    final asideBand = asideW >= longestWord
        ? math.max(math.max(layoutLeft(asideW), heroH), ch)
        : double.infinity;
    // Whichever costs the shorter band: the title wrapping to more lines
    // beside the controls, or the controls on a row of their own.
    final aside = asideBand <= belowBand;
    final editBand = aside ? asideBand : belowBand;
    final band = math.max(normalBand, editBand);
    size = constraints.constrain(Size(maxW, band));

    /// Title and hero as they sit outside edit mode, in the band's top
    /// [normalBand].
    void placeNormal() {
      final leftH = layoutLeft(heroBeside ? normalW : maxW);
      if (stackedHero) {
        _place(title, 0, 0);
        _place(freshness, 0, title.size.height);
        _place(hero, 0, leftH + _belowGap);
        return;
      }
      final top = (normalBand - leftH) / 2;
      _place(title, 0, top);
      _place(freshness, 0, top + title.size.height);
      _place(hero, maxW - heroW, (normalBand - heroH) / 2);
    }

    if (!editing) {
      placeNormal();
      controls.layout(BoxConstraints.tight(Size.zero));
      _place(controls, 0, 0);
      return;
    }

    controls.layout(const BoxConstraints(), parentUsesSize: true);
    if (aside) {
      final leftH = layoutLeft(asideW);
      final top = (band - leftH) / 2;
      _place(title, 0, top);
      _place(freshness, 0, top + title.size.height);
      final controlsX = maxW - cw;
      _place(controls, controlsX, (band - ch) / 2);
      _place(hero, hasHero ? controlsX - _headerGap - heroW : 0, (band - heroH) / 2);
      return;
    }
    placeNormal();
    if (sharesHeroRow) {
      final rowTop = topLeftH + _belowGap;
      final rowH = math.max(heroH, ch);
      _place(hero, 0, rowTop + (rowH - heroH) / 2);
      _place(controls, maxW - cw, rowTop + (rowH - ch) / 2);
    } else {
      _place(controls, maxW - cw, normalBand + _belowGap);
    }
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
