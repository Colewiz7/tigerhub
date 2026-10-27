/// Right-click, long-press and keyboard context menus for rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../motion/reduce_motion.dart';
import '../services/clipboard.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

class MenuAction {
  const MenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  // the one copy action every row shares
  factory MenuAction.copy(String text, {String label = 'Copy text'}) =>
      MenuAction(
        label: label,
        icon: AppIconKind.copy,
        onSelected: (context) => copyWithFeedback(context, text),
      );

  final String label;
  final AppIconKind icon;
  final void Function(BuildContext context) onSelected;
}

// the dashboard turns this off in edit mode, where long-press means drag
class ContextActionsScope extends InheritedWidget {
  const ContextActionsScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ContextActionsScope>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(ContextActionsScope oldWidget) =>
      enabled != oldWidget.enabled;
}

class ShowContextMenuIntent extends Intent {
  const ShowContextMenuIntent();
}

class ContextActions extends StatefulWidget {
  const ContextActions({
    super.key,
    required this.actions,
    required this.child,
    this.focusable = false,
  });

  final List<MenuAction> actions;
  final Widget child;

  // for children with no focus stop of their own, so keys can reach them
  final bool focusable;

  static const double itemHeight = 48;

  // focus ring tokens from the spec: 2px wide, 2px clear of the row
  static const double ringWidth = 2;
  static const double ringGap = 2;
  // Flutter paints a border inside its box, so the decoration radius is the
  // ring's outer edge: row radius + gap + stroke (inner edge is row + gap)
  static const double ringOuterRadius = Shapes.innerRadius + ringGap + ringWidth;
  static const ringKey = ValueKey('context-focus-ring');

  @override
  State<ContextActions> createState() => _ContextActionsState();
}

class _ContextActionsState extends State<ContextActions> {
  bool _open = false;
  bool _focused = false;

  Future<void> _show(Offset globalPosition) async {
    if (_open || !ContextActionsScope.enabledOf(context)) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    // the overlay may sit inside a phone frame, so the pointer needs converting
    final local = overlay.globalToLocal(globalPosition);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduce = reduceMotion(context);
    final actions = widget.actions;

    _open = true;
    HapticFeedback.lightImpact();
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(local, local),
        Offset.zero & overlay.size,
      ),
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Shapes.inner),
      popUpAnimationStyle: reduce
          ? const AnimationStyle(
              duration: Duration.zero,
              reverseDuration: Duration.zero,
            )
          : null,
      items: [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: ContextActions.itemHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(actions[i].icon.of(context), size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Flexible(child: Text(actions[i].label, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
    _open = false;
    if (picked == null || !mounted) return;
    actions[picked].onSelected(context);
  }

  void _showAtFocus() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _show(box.localToGlobal(box.size.center(Offset.zero)));
  }

  Widget _focusStop(bool enabled) {
    final ring =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: enabled,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (ring)
            Positioned.fill(
              left: -(ContextActions.ringGap + ContextActions.ringWidth),
              top: -(ContextActions.ringGap + ContextActions.ringWidth),
              right: -(ContextActions.ringGap + ContextActions.ringWidth),
              bottom: -(ContextActions.ringGap + ContextActions.ringWidth),
              child: IgnorePointer(
                child: DecoratedBox(
                  key: ContextActions.ringKey,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ContextActions.ringOuterRadius),
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: ContextActions.ringWidth),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    if (actions.isEmpty) return widget.child;
    final enabled = ContextActionsScope.enabledOf(context);

    return Shortcuts(
      shortcuts: enabled
          ? const {
              SingleActivator(LogicalKeyboardKey.contextMenu):
                  ShowContextMenuIntent(),
              SingleActivator(LogicalKeyboardKey.f10, shift: true):
                  ShowContextMenuIntent(),
            }
          : const {},
      child: Actions(
        actions: {
          ShowContextMenuIntent: CallbackAction<ShowContextMenuIntent>(
            onInvoke: (_) {
              _showAtFocus();
              return null;
            },
          ),
        },
        child: Semantics(
          customSemanticsActions: enabled
              ? {
                  for (final action in actions)
                    CustomSemanticsAction(label: action.label): () =>
                        action.onSelected(context),
                }
              : null,
          child: GestureDetector(
            onSecondaryTapUp: enabled
                ? (details) => _show(details.globalPosition)
                : null,
            onLongPressStart: enabled
                ? (details) => _show(details.globalPosition)
                : null,
            child: widget.focusable ? _focusStop(enabled) : widget.child,
          ),
        ),
      ),
    );
  }
}
