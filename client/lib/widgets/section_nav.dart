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

import '../motion/reduce_motion.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
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
    this.navWidth = 330,
    this.twoPaneFrom = 900,
    this.iconSize = 18,
  });

  final List<SectionSpec> sections;
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
    if (widget.sections.isEmpty) return const SizedBox.shrink();
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

    final section = widget.sections.firstWhere(
      (s) => s.id == _selected,
      orElse: () => widget.sections.first,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: widget.navWidth,
          child: _NavList(
            sections: widget.sections,
            selected: section.id,
            iconSize: widget.iconSize,
            onSelect: (s) => setState(() => _selected = s.id),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _SectionPaneStack(
              sections: widget.sections,
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
    required this.selected,
    required this.onSelect,
    required this.iconSize,
  });

  final List<SectionSpec> sections;
  final String? selected;
  final ValueChanged<SectionSpec> onSelect;
  final double iconSize;

  @override
  Widget build(BuildContext context) => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(16, 6, 16, 24)),
    children: [
      for (final section in sections)
        SectionNavRow(
          spec: section,
          active: section.id == selected,
          iconSize: iconSize,
          onTap: () => onSelect(section),
        ),
    ],
  );
}

class SectionNavRow extends StatelessWidget {
  const SectionNavRow({
    super.key,
    required this.spec,
    required this.active,
    required this.onTap,
    this.iconSize = 18,
  });

  final SectionSpec spec;
  final bool active;
  final VoidCallback onTap;
  final double iconSize;

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
        button: true,
        selected: active,
        label: '${spec.title}, ${spec.subtitle}',
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
