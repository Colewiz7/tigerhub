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
import 'app_icon.dart';
import 'freshness.dart';

// handle and customize on top, remove under the handle
// 32 each, 48 between centers so the touch squares meet
const double editControlsWidth = 32 * 2 + 16;
const double editControlsHeight = 32 * 2 + 16;

// the old single row, only to keep normal mode heights
const double _rowControlsWidth = 32 * 3 + 6 * 2;
const double _rowControlsHeight = 32;

/// Gap between the title column, the hero and the edit controls.
const double _headerGap = 10;

/// Gap between the title and the controls when they sit under it.
const double _belowGap = 6;

/// Wide layout only (600pt and up, unchanged from before the phone condense):
/// the title width at which the edit controls still sit beside the title and
/// hero. Narrower than this they drop under the title when the band has room.
const double _asideTitleWidth = 96;

/// Wide layout only: the least a title may keep beside the controls before the
/// hero scales down.
const double _titleFloor = 48;

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
    this.onOpen,
    this.openLabel,
  });

  /// Whether the card above [context] is a phone card whose header links to
  /// the rest, so its list drops the "+N" footer.
  static bool linkedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardLinked>() != null;

  /// Whether rows here sit flat in a phone card, an inset group with
  /// hairlines, rather than each being its own filled surface.
  static bool flatRowsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FlatRows>() != null;

  final String title;

  /// Phones: the header (title and a chevron) opens the full list. Inert in
  /// edit mode. Wider windows keep the "+N" footer instead.
  final VoidCallback? onOpen;

  /// Where [onOpen] goes, read after the title: "opens Dining".
  final String? openLabel;

  /// Section identity. Cards without one show the title alone.
  final AppIconKind? glyph;
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
    if (!Insets.phone(context)) return _card(context);
    // phones only, wide stays as it was
    return _FlatRows(child: onOpen == null ? _card(context) : _linked(context));
  }

  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              legacy: !Insets.phone(context),
              title: _CardTitle(
                title: title,
                glyph: glyph,
                legacy: !Insets.phone(context),
              ),
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
              // Skeleton to content swaps in place, with no crossfade.
              child: KeyedSubtree(
                key: ValueKey(state == DataState.priming),
                child: child,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // the same geometry, padding split around a tappable header band
  Widget _linked(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = Insets.cardPaddingFor(context);
    final editing = dragHandle != null;
    final header = _CardHeader(
      hasHero: hero != null,
      editing: editing,
      legacy: false,
      title: Semantics(
        container: true,
        button: !editing,
        label: openLabel == null ? title : '$title, $openLabel',
        excludeSemantics: true,
        onTap: editing ? null : onOpen,
        // title and chevron only, as the wireframe draws it
        child: _CardTitle(title: title, glyph: null, legacy: false, chevron: true, chevronHidden: editing),
      ),
      freshness: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: FreshnessLine(state: state, fetchedAt: fetchedAt),
      ),
      hero: hero == null
          ? const SizedBox.shrink()
          : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: hero!),
      controls: dragHandle ?? const SizedBox.shrink(),
    );
    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      borderRadius: Shapes.cardFor(context),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // card top to content is 56, all of it the link
            InkWell(
              onTap: editing ? null : onOpen,
              excludeFromSemantics: true,
              canRequestFocus: !editing,
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, 8),
                child: header,
              ),
            ),
            _FlexibleIfBounded(
              bounded: box.maxHeight.isFinite,
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                // rows stay apart from the link and the cards move actions
                child: Semantics(
                  container: true,
                  child: _CardLinked(
                    child: KeyedSubtree(
                      key: ValueKey(state == DataState.priming),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardLinked extends InheritedWidget {
  const _CardLinked({required super.child});

  @override
  bool updateShouldNotify(_CardLinked oldWidget) => false;
}

class _FlatRows extends InheritedWidget {
  const _FlatRows({required super.child});

  @override
  bool updateShouldNotify(_FlatRows oldWidget) => false;
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
  const _CardTitle({
    required this.title,
    required this.glyph,
    required this.legacy,
    this.chevron = false,
    this.chevronHidden = false,
  });

  final String title;
  final AppIconKind? glyph;
  final bool chevron;

  /// Edit mode, where the link does nothing.
  final bool chevronHidden;

  /// The 600pt and wider title, as it was before the phone condense: given a
  /// finite height it keeps only the lines that fit and ellipsizes past them.
  final bool legacy;

  @override
  Widget build(BuildContext context) {
    if (legacy) return _legacyTitle(context);
    final base = Theme.of(context).textTheme.titleLarge;
    // Phones: title 22, no tracking.
    final style = Insets.phone(context)
        ? base?.copyWith(fontSize: 22, letterSpacing: 0)
        : base;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (glyph != null) ...[
          SizedBox(width: 22, height: 22, child: AppIcon(glyph!, size: 22)),
          const SizedBox(width: 9),
        ],
        Flexible(child: Text(title, style: style)),
        if (chevron) ...[
          const SizedBox(width: 4),
          // keeps its room, so editing moves nothing
          Visibility.maintain(
            key: const ValueKey('card-link-chevron'),
            visible: !chevronHidden,
            child: Icon(
              AppIconKind.chevron.of(context),
              size: 17,
              applyTextScaling: true,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _legacyTitle(BuildContext context) {
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
              AppIcon(glyph!, size: 22),
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
/// Outside edit mode the header is as tall as it was when the controls were
/// one 32 tall row. Edit mode is at least that tall and grows when the 80 by
/// 80 controls block needs more.
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
    required this.legacy,
    required Widget title,
    required Widget freshness,
    required Widget hero,
    required Widget controls,
  }) : super(children: [title, freshness, hero, controls]);

  final bool hasHero;
  final bool editing;

  /// 600pt and wider: the header as it was before the phone condense. Edit
  /// mode keeps the normal height by ellipsizing the title to its normal line
  /// count and, as a last resort, scaling the hero down.
  final bool legacy;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardHeader(hasHero: hasHero, editing: editing, legacy: legacy);

  @override
  void updateRenderObject(BuildContext context, _RenderCardHeader renderObject) {
    renderObject
      ..hasHero = hasHero
      ..editing = editing
      ..legacy = legacy;
  }
}

class _RenderCardHeader extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderCardHeader({
    required bool hasHero,
    required bool editing,
    required bool legacy,
  }) {
    _hasHero = hasHero;
    _editing = editing;
    _legacy = legacy;
  }

  late bool _legacy;
  bool get legacy => _legacy;
  set legacy(bool value) {
    if (value == _legacy) return;
    _legacy = value;
    markNeedsLayout();
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

  /// The header as it was for every width before the phone condense, kept for
  /// 600pt and wider so those layouts are unchanged.
  void _performLegacyLayout() {
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
    final normalBand = math.max(leftH, heroNatural.height);
    var band = normalBand;
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
    // edit mode may grow the band for the block
    band = math.max(normalBand, ch);
    size = constraints.constrain(Size(maxW, band));
    _place(hero, heroX, (band - heroNatural.height) / 2);
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
  void performLayout() {
    if (legacy) return _performLegacyLayout();
    final title = firstChild!;
    final freshness = childAfter(title)!;
    final hero = childAfter(freshness)!;
    final controls = childAfter(hero)!;
    final maxW = constraints.maxWidth;

    // At most the header's width: a long pill at large text ("12 days to go")
    // is wider than a phone card, and its FittedBox scales it down to fit
    // rather than letting it leave the card.
    hero.layout(BoxConstraints(maxWidth: maxW), parentUsesSize: true);
    final heroW = hero.size.width;
    final heroH = hero.size.height;
    final heroGap = hasHero ? _headerGap : 0.0;

    /// Lays the title and freshness line out in [width]; returns their height.
    double layoutLeft(double width) {
      title.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      freshness.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      return title.size.height + freshness.size.height;
    }

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

    // controls of cw by ch sit beside the hero when the title keeps its
    // longest word there (aside), else under the title and hero (below),
    // else with the hero stacked they share its row if both fit
    // whichever band is shorter wins
    ({bool aside, bool sharesHeroRow, double asideW, double band}) plan(double cw, double ch) {
      final asideW = maxW - cw - _headerGap - heroW - heroGap;
      final sharesHeroRow = stackedHero && heroW + _headerGap + cw <= maxW;
      final belowBand = sharesHeroRow
          ? topLeftH + _belowGap + math.max(heroH, ch)
          : normalBand + _belowGap + ch;
      final asideBand = asideW >= longestWord
          ? math.max(math.max(layoutLeft(asideW), heroH), ch)
          : double.infinity;
      final aside = asideBand <= belowBand;
      return (aside: aside, sharesHeroRow: sharesHeroRow, asideW: asideW, band: aside ? asideBand : belowBand);
    }

    // normal mode keeps what the old one row asked for, so no card moves
    final rowBand = math.max(normalBand, plan(_rowControlsWidth, _rowControlsHeight).band);
    final edit = editing ? plan(editControlsWidth, editControlsHeight) : null;
    final band = edit == null ? rowBand : math.max(rowBand, edit.band);
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
    const cw = editControlsWidth;
    const ch = editControlsHeight;
    if (edit!.aside) {
      final leftH = layoutLeft(edit.asideW);
      final top = (band - leftH) / 2;
      _place(title, 0, top);
      _place(freshness, 0, top + title.size.height);
      final controlsX = maxW - cw;
      _place(controls, controlsX, (band - ch) / 2);
      _place(hero, hasHero ? controlsX - _headerGap - heroW : 0, (band - heroH) / 2);
      return;
    }
    placeNormal();
    if (edit.sharesHeroRow) {
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
