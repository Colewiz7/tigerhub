/// Nav list plus content pane, the app's one navigation idiom for a screen
/// that holds several unrelated things.
///
/// Two panes when there is width, a list that pushes to detail when there is
/// not. Rows are the same container plus circular icon badge used everywhere
/// else, and selection is a filled tinted container rather than an underline,
/// which is reserved for the tab bar.
///
/// Extracted from the settings screen once the Campus tab grew to five stacked
/// sections in one scroll and things started disappearing below the fold.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../motion/reduce_motion.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
import 'context_actions.dart';
import 'hidden_group.dart';
import 'status_row.dart';
import 'tab_bar.dart';

class SectionSpec {
  const SectionSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  final String id;
  final String title;
  final String subtitle;
  final AppIconKind icon;

  final WidgetBuilder builder;
}

class SectionScaffold extends StatefulWidget {
  const SectionScaffold({
    super.key,
    required this.sections,
    this.hidden = const [],
    this.rowActions,
    this.header,
    this.editing = false,
    this.onMove,
    this.navWidth = 330,
    this.twoPaneFrom = 900,
    this.iconSize = 18,
  });

  final List<SectionSpec> sections;

  /// Rows the reader hid. They sit under a collapsed Hidden (n) header.
  final List<SectionSpec> hidden;

  /// Context menu for a row. Null leaves the rows without one.
  final List<MenuAction> Function(SectionSpec spec, bool hidden)? rowActions;

  /// Sits above the rows.
  final Widget? header;

  /// Rows carry Move up, Move down and their actions as buttons, and open nothing.
  final bool editing;

  /// Step is -1 for up and 1 for down.
  final void Function(SectionSpec spec, int step)? onMove;
  final double navWidth;
  final double twoPaneFrom;

  /// Glyph size in each nav row's circle.
  final double iconSize;

  @override
  State<SectionScaffold> createState() => _SectionScaffoldState();
}

class _SectionScaffoldState extends State<SectionScaffold> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty && widget.hidden.isEmpty) return const SizedBox.shrink();
    // Measured from the space actually handed to this widget, not from the
    // window. It sits inside a tab under a masthead, so the window size is the
    // wrong number, and MediaQuery also reports logical pixels scaled by the
    // device pixel ratio, which made the breakpoint behave differently under
    // test than on screen.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _build(context, constraints.maxWidth >= widget.twoPaneFrom),
    );
  }

  Widget _build(BuildContext context, bool wide) {
    if (!wide) {
      return _NavList(
        sections: widget.sections,
        hidden: widget.hidden,
        rowActions: widget.rowActions,
        header: widget.header,
        editing: widget.editing,
        onMove: widget.onMove,
        selected: null,
        iconSize: widget.iconSize,
        onSelect: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(section.title)),
              body: section.builder(context),
            ),
          ),
        ),
      );
    }

    final all = [...widget.sections, ...widget.hidden];
    final section = all.firstWhere((s) => s.id == _selected, orElse: () => all.first);
    // a hidden row only gets a pane while it is the one open
    final panes = [
      ...widget.sections,
      if (widget.hidden.any((s) => s.id == section.id)) section,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: widget.navWidth,
          child: _NavList(
            sections: widget.sections,
            hidden: widget.hidden,
            rowActions: widget.rowActions,
            header: widget.header,
            editing: widget.editing,
            onMove: widget.onMove,
            selected: section.id,
            iconSize: widget.iconSize,
            onSelect: (s) => setState(() => _selected = s.id),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _SectionPaneStack(
              sections: panes,
              selectedId: section.id,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionPaneStack extends StatelessWidget {
  const _SectionPaneStack({required this.sections, required this.selectedId});

  final List<SectionSpec> sections;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final section in sections)
          Visibility(
            visible: section.id == selectedId,
            maintainState: true,
            child: AnimatedOpacity(
              key: ValueKey(section.id),
              opacity: section.id == selectedId ? 1 : 0,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: section.builder(context),
            ),
          ),
      ],
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({
    required this.sections,
    required this.hidden,
    required this.rowActions,
    required this.header,
    required this.editing,
    required this.onMove,
    required this.selected,
    required this.onSelect,
    required this.iconSize,
  });

  final List<SectionSpec> sections;
  final List<SectionSpec> hidden;
  final List<MenuAction> Function(SectionSpec spec, bool hidden)? rowActions;
  final Widget? header;
  final bool editing;
  final void Function(SectionSpec spec, int step)? onMove;
  final String? selected;
  final ValueChanged<SectionSpec> onSelect;
  final double iconSize;

  Widget _row(BuildContext context, SectionSpec section, {required bool isHidden}) {
    final key = ValueKey('${isHidden ? 'hidden' : 'nav'}-${section.id}');
    final actions = rowActions?.call(section, isHidden) ?? const <MenuAction>[];
    if (!editing) {
      final row = SectionNavRow(
        key: key,
        spec: section,
        active: section.id == selected,
        iconSize: iconSize,
        onTap: () => onSelect(section),
      );
      return actions.isEmpty ? row : ContextActions(actions: actions, child: row);
    }

    // a hidden row has no place in the order, so it only offers its actions
    final at = sections.indexOf(section);
    final up = !isHidden && at > 0 ? () => onMove?.call(section, -1) : null;
    final down = !isHidden && at >= 0 && at < sections.length - 1 ? () => onMove?.call(section, 1) : null;
    return SectionNavRow(
      key: key,
      spec: section,
      active: section.id == selected,
      iconSize: iconSize,
      onTap: null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isHidden) ...[
            _EditButton(icon: AppIconKind.arrowUp, label: 'Move up', onTap: up),
            _EditButton(icon: AppIconKind.arrowDown, label: 'Move down', onTap: down),
          ],
          for (final action in actions)
            _EditButton(icon: action.icon, label: action.label, onTap: () => action.onSelected(context)),
        ],
      ),
      customActions: {
        const CustomSemanticsAction(label: 'Move up'): ?up,
        const CustomSemanticsAction(label: 'Move down'): ?down,
        for (final action in actions) CustomSemanticsAction(label: action.label): () => action.onSelected(context),
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(16, 6, 16, 24)),
    children: [
      ?header,
      for (final section in sections) _row(context, section, isHidden: false),
      if (hidden.isNotEmpty)
        HiddenGroup(
          count: hidden.length,
          children: [for (final section in hidden) _row(context, section, isHidden: true)],
        ),
    ],
  );
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.icon, required this.label, required this.onTap});

  final AppIconKind icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: AppIcon(icon, size: 20, color: onTap == null ? scheme.onSurface.withValues(alpha: 0.38) : scheme.primary),
      ),
    );
  }
}

class SectionNavRow extends StatelessWidget {
  const SectionNavRow({
    super.key,
    required this.spec,
    required this.active,
    required this.onTap,
    this.iconSize = 18,
    this.trailing,
    this.customActions = const {},
  });

  final SectionSpec spec;
  final bool active;
  // null while editing, when the row opens nothing
  final VoidCallback? onTap;
  final double iconSize;

  // edit mode buttons
  final Widget? trailing;

  // what assistive tech gets in place of the tap while editing
  final Map<CustomSemanticsAction, VoidCallback> customActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // one line at the default size, a second once the reader turns text up
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1;

    final background = active
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.surfaceContainerHigh;
    final badge = active
        ? scheme.primary
        : scheme.primary.withValues(alpha: 0.30);
    final iconColor = active ? scheme.onPrimary : scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: StatusRow.gap),
      child: Semantics(
        container: onTap == null,
        button: onTap != null,
        selected: active,
        label: '${spec.title}, ${spec.subtitle}',
        customSemanticsActions: customActions.isEmpty ? null : customActions,
        child: Material(
          elevation: 0,
          color: background,
          borderRadius: Shapes.inner,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: StatusRow.badgeSize,
                    height: StatusRow.badgeSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: badge,
                    ),
                    // same glyph size as StatusRow
                    child: AppIcon(spec.icon, size: iconSize, color: iconColor),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(spec.title, style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          spec.subtitle,
                          style: text.bodySmall,
                          maxLines: largeText ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // large text has no room beside the title for the buttons
                        if (largeText && trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
                      ],
                    ),
                  ),
                  if (!largeText) ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
