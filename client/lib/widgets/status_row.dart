/// A list row as its own container.
///
/// Every dining location, event, and chef is one of these rather than a bare
/// line of text. The circular icon badge on the left is the anchor the eye
/// lands on, and the two-line title/subtitle split is what gives a row internal
/// hierarchy instead of a single flat run of words.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';
import 'card_shell.dart';
import 'context_actions.dart';
import 'status_text.dart';

/// How prominent a row is. Dimmed rows recede without disappearing. Quiet
/// rows recede by colour only, so their text keeps full contrast.
enum RowEmphasis { normal, dimmed, quiet }

class StatusRow extends StatelessWidget {
  const StatusRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
    this.emphasis = RowEmphasis.normal,
    this.onTap,
    this.semanticHint,
    this.dense = false,
    this.subtitleMaxLines = 2,
    this.actions = const [],
    this.iconSize = 18,
    this.wrapSubtitle = false,
    this.grouped = false,
  });

  // a row in an inset group: no fill or gap of its own, the group draws both
  final bool grouped;

  /// Glyph size in the badge circle.
  final double iconSize;

  /// Standard rows only: the subtitle takes a second line once text is turned
  /// up. Off where a list budgets a fixed row height.
  final bool wrapSubtitle;

  /// max subtitle lines, null shows all
  /// null only outside BoundedList
  final int? subtitleMaxLines;

  /// The dashboard's condensed row on phones (under 600pt): 52 tall with a 4
  /// gap, a 32 icon circle, title 17 and subtitle 14 with no tracking. Wider
  /// windows, and rows outside the dashboard, keep the standard row.
  final bool dense;

  /// The dense row at 1x text, without its gap.
  static const double denseHeight = 52;
  static const double denseGap = 4;
  static const double denseBadgeSize = 32;

  bool _isDense(BuildContext context) => dense && Insets.phone(context);

  final AppIconKind icon;
  final String title;
  final String? subtitle;

  /// Usually a time or a chip. Kept short.
  final Widget? trailing;

  /// Tints the icon badge. Defaults to the scheme primary.
  final Color? accent;

  final RowEmphasis emphasis;
  final VoidCallback? onTap;
  final String? semanticHint;

  /// Right-click, long-press and keyboard menu. Empty means no menu.
  final List<MenuAction> actions;

  /// The height BoundedList should budget, including the gap beneath.
  ///
  /// Use [heightFor] wherever a BuildContext is available. This is the base
  /// figure at the system's default text size.
  static const double height = 72;

  /// [height], grown to fit the reader's text size.
  ///
  /// The row pins its title and subtitle into a fixed box so BoundedList's
  /// arithmetic stays exact. That box is sized for text at 1.0, so turning the
  /// system font up overflowed it: measured at 1.3, every list in the app
  /// spilled 6 to 7 pixels and drew the debug stripe. Android's display
  /// settings go well past 1.3, and someone who has turned text up is still
  /// holding a phone that has to work.
  ///
  /// Scaling the budget rather than shrinking the text keeps both properties:
  /// the rows still have an exact height for BoundedList to divide by, and the
  /// text is still the size the reader asked for.
  static double heightFor(BuildContext context, {bool dense = false}) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Below 1 the rows would get tighter than they were designed for, and
    // above 2 a single row would eat a whole card.
    final clamped = scale.clamp(1.0, 2.0);
    if (dense && Insets.phone(context)) return denseHeight * clamped + denseGap;
    return height * clamped;
  }

  static const double gap = 8;
  static const double badgeSize = 42;

  // dinings food truck rows draw 18 in 32, this is that ratio in 42
  static const double fillIconSize = 24;

  @override
  Widget build(BuildContext context) =>
      ContextActions(
        actions: actions,
        focusable: onTap == null,
        child: _row(context),
      );

  Widget _row(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final quiet = emphasis == RowEmphasis.quiet;
    final dimmed = emphasis == RowEmphasis.dimmed || quiet;
    final tint = accent ?? scheme.primary;
    final dense = _isDense(context);
    // in a phone card the row is no surface of its own
    final flat = grouped || (dense && CardShell.flatRowsOf(context));
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1;
    final rowGap = flat ? 0.0 : (dense ? denseGap : gap);
    final inset = grouped ? 12.0 : 0.0;
    final badge = dense ? denseBadgeSize : badgeSize;
    final titleStyle = (dense
        ? text.titleMedium?.copyWith(
            fontSize: 17,
            height: 1.3,
            letterSpacing: 0,
          )
        : text.titleMedium)?.copyWith(color: quiet ? scheme.onSurfaceVariant : null);
    final subtitleStyle = dense
        ? text.bodySmall?.copyWith(fontSize: 14, height: 1.3, letterSpacing: 0)
        : text.bodySmall;
    // Dense rows size to their text (see _DenseBody): 52 stays the height of a
    // row whose name and status each fit one line, grown with the text size.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final minHeight = dense ? denseHeight * scale.clamp(1.0, 2.0) : 0.0;

    // A dimmed row keeps its shape but loses contrast, so open and closed are
    // separable at a glance without reading either.
    final opacity = emphasis == RowEmphasis.dimmed ? 0.55 : 1.0;

    return Padding(
      padding: EdgeInsets.only(bottom: rowGap),
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: subtitle == null ? title : '$title, $subtitle',
        hint: semanticHint,
        child: Material(
          elevation: 0,
          color: flat ? Colors.transparent : scheme.surfaceContainerHigh,
          borderRadius: grouped ? BorderRadius.zero : Shapes.inner,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                // BoundedList budgets 72px including the 8px row gap. Ten
                // vertical pixels left only 44px for two text lines whose
                // configured line heights need 48, causing quiet 4px overflows
                // on longer copy. Eight preserves the touch target and gives
                // the typography its actual measured height.
                padding: EdgeInsets.symmetric(
                  // flat rows line up with the card title
                  horizontal: grouped ? inset : (flat ? 0 : (dense ? 10 : 12)),
                  vertical: dense ? 4 : 8,
                ),
                child: Row(
                  children: [
                    Opacity(
                      opacity: opacity,
                      child: Container(
                        width: badge,
                        height: badge,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // Strong on purpose. Sampled from Caelestia, the badge is
                          // far brighter than the row it sits on, and that contrast is
                          // what the eye actually lands on.
                          color: tint.withValues(alpha: dimmed ? 0.20 : 0.32),
                        ),
                        // 18 in a 42px circle. At 21 the glyph very nearly filled
                        // its box, leaving a ring too thin to read as a badge.
                        child: AppIcon(icon, size: iconSize, color: tint),
                      ),
                    ),
                    SizedBox(width: dense ? 10 : 13),
                    if (dense)
                      Expanded(
                        child: Opacity(
                          opacity: opacity,
                          child: _DenseBody(
                            title: Text(
                              title,
                              style: titleStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: subtitle == null
                                ? null
                                : StatusText(
                                    subtitle!,
                                    style: subtitleStyle,
                                    maxLines: subtitleMaxLines,
                                    // ellipsis needs a cap
                                    overflow: subtitleMaxLines == null
                                        ? TextOverflow.clip
                                        : TextOverflow.ellipsis,
                                  ),
                            trailing: trailing,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Opacity(
                          opacity: opacity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: titleStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                StatusText(
                                  subtitle!,
                                  style: subtitleStyle,
                                  // one line, two at large text when the row
                                  // wraps, all of it when null
                                  maxLines: subtitleMaxLines == null
                                      ? null
                                      : (wrapSubtitle && largeText ? 2 : 1),
                                  overflow: subtitleMaxLines == null
                                      ? TextOverflow.clip
                                      : TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (trailing != null && !dense) ...[
                      const SizedBox(width: 10),
                      // Trailing metadata must never consume the title's entire
                      // lane on a narrow screen. Event timestamps exposed this:
                      // an unconstrained Text measured at 283px and reduced the
                      // Expanded title to zero width.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 132),
                        child: Opacity(opacity: opacity, child: trailing!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline between two flat rows, inset to where their text starts. It
/// takes the place of the row gap, so the row pitch is unchanged.
class RowSeparator extends StatelessWidget {
  const RowSeparator({super.key});

  // badge plus the gap after it
  static const double inset = StatusRow.denseBadgeSize + 10;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: StatusRow.denseGap,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: inset),
        child: SizedBox(
          height: 1 / MediaQuery.devicePixelRatioOf(context),
          width: double.infinity,
          child: ColoredBox(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
    ),
  );
}

/// The text of a dense row: name, status and the trailing widget.
///
/// The trailing widget (an occupancy pill, an "ENDED" label) sits beside the
/// text when the name still shows in full there (up to two lines, not cut) and
/// the status needs no more lines than it does at the full width. Otherwise it
/// moves under the status. This is measured when the row is laid out, so no
/// text size is a threshold, and the trailing widget never makes a name
/// ellipsize that would fit without it.
class _DenseBody extends MultiChildRenderObjectWidget {
  _DenseBody({required Widget title, Widget? subtitle, Widget? trailing})
    : hasSubtitle = subtitle != null,
      hasTrailing = trailing != null,
      super(
        children: [
          title,
          subtitle ?? const SizedBox.shrink(),
          trailing ?? const SizedBox.shrink(),
        ],
      );

  final bool hasSubtitle;
  final bool hasTrailing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDenseBody(hasSubtitle: hasSubtitle, hasTrailing: hasTrailing);

  @override
  void updateRenderObject(BuildContext context, _RenderDenseBody renderObject) {
    renderObject
      ..hasSubtitle = hasSubtitle
      ..hasTrailing = hasTrailing;
  }
}

class _RenderDenseBody extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderDenseBody({required bool hasSubtitle, required bool hasTrailing}) {
    _hasSubtitle = hasSubtitle;
    _hasTrailing = hasTrailing;
  }

  /// Between the text and a trailing widget beside it.
  static const double _gap = 10;

  /// Between the status and a trailing widget under it.
  static const double _stackGap = 4;

  /// Between the name and the status.
  static const double _lineGap = 2;

  /// A trailing widget never takes more than this of the row, so a long stamp
  /// cannot squeeze the text to nothing.
  static const double _maxTrailing = 132;

  late bool _hasSubtitle;
  bool get hasSubtitle => _hasSubtitle;
  set hasSubtitle(bool value) {
    if (value == _hasSubtitle) return;
    _hasSubtitle = value;
    markNeedsLayout();
  }

  late bool _hasTrailing;
  bool get hasTrailing => _hasTrailing;
  set hasTrailing(bool value) {
    if (value == _hasTrailing) return;
    _hasTrailing = value;
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

  static RenderParagraph? _paragraph(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) => found ??= _paragraph(child));
    return found;
  }

  @override
  void performLayout() {
    final title = firstChild!;
    final subtitle = childAfter(title)!;
    final trailing = childAfter(subtitle)!;
    final w = constraints.maxWidth;

    var trailW = 0.0;
    var trailH = 0.0;
    if (hasTrailing) {
      trailing.layout(
        BoxConstraints(maxWidth: math.min(_maxTrailing, w)),
        parentUsesSize: true,
      );
      trailW = trailing.size.width;
      trailH = trailing.size.height;
    } else {
      trailing.layout(BoxConstraints.tight(Size.zero));
    }
    if (!hasSubtitle) subtitle.layout(BoxConstraints.tight(Size.zero));

    // Lays the name and status (two lines each at most) out in [width]: the
    // text's height, whether either was cut, and the status's height.
    ({double height, bool cut, bool statusCut, double statusHeight}) layoutText(
      double width,
    ) {
      title.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      var height = title.size.height;
      var statusHeight = 0.0;
      var statusCut = false;
      if (hasSubtitle) {
        subtitle.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
        statusHeight = subtitle.size.height;
        statusCut = _paragraph(subtitle)?.didExceedMaxLines ?? false;
        height += _lineGap + statusHeight;
      }
      return (
        height: height,
        cut: _paragraph(title)?.didExceedMaxLines ?? false,
        statusCut: statusCut,
        statusHeight: statusHeight,
      );
    }

    final full = layoutText(w);
    var text = full;
    var beside = false;
    if (hasTrailing) {
      final narrow = layoutText(math.max(0.0, w - trailW - _gap));
      // Compare what each lane shows. The beside lane is the narrower one, so
      // it never shows more of the name or the status than the stacked lane:
      // when either is cut beside, stacked shows at least as much (and more,
      // even if it is cut there too, since it has the wider lines). Beside wins
      // only when both lines are whole there and the status takes no more
      // lines than it does at the full width.
      beside =
          !narrow.cut &&
          !narrow.statusCut &&
          narrow.statusHeight <= full.statusHeight + 0.5;
      text = beside ? narrow : layoutText(w);
    }

    final titleH = title.size.height;
    if (beside) {
      final height = math.max(text.height, trailH);
      final top = (height - text.height) / 2;
      _place(title, 0, top);
      _place(subtitle, 0, top + titleH + _lineGap);
      _place(trailing, w - trailW, (height - trailH) / 2);
      size = constraints.constrain(Size(w, height));
      return;
    }
    _place(title, 0, 0);
    _place(subtitle, 0, titleH + _lineGap);
    var height = text.height;
    if (hasTrailing) {
      _place(trailing, 0, height + _stackGap);
      height += _stackGap + trailH;
    }
    size = constraints.constrain(Size(w, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A tinted header that introduces a group of rows.
///
/// Deliberately heavier than the small uppercase label it replaces: an
/// organizer name is a navigation landmark, not a footnote.
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.icon,
    required this.title,
    this.count,
    this.dense = false,
  });

  final AppIconKind icon;
  final String title;
  final int? count;

  /// The dashboard's condensed phone header: 40 tall (the spec's group header)
  /// with a 4 gap below, title 17.
  final bool dense;

  static const double height = 46;
  static const double gap = 6;
  static const double denseHeight = 40;
  static const double denseGap = 4;

  /// The height a list should budget for one header and the gap under it.
  static double blockHeight(BuildContext context, {bool dense = false}) {
    if (dense && Insets.phone(context)) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      return denseHeight * scale + denseGap;
    }
    return height + gap;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final compact = dense && Insets.phone(context);
    final titleStyle = compact
        ? text.titleMedium?.copyWith(
            fontSize: 17,
            height: 1.3,
            letterSpacing: 0,
          )
        : text.titleMedium;

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? denseGap : gap),
      child: Semantics(
        header: true,
        label: count == null ? title : '$title, $count items',
        child: Container(
          constraints: compact
              ? const BoxConstraints(minHeight: denseHeight)
              : null,
          alignment: compact ? Alignment.centerLeft : null,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            borderRadius: Shapes.small,
          ),
          child: Row(
            children: [
              AppIcon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: titleStyle?.copyWith(color: scheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: titleStyle?.copyWith(
                    color: scheme.primary.withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
