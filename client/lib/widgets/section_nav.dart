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

import '../theme/tokens.dart';
import 'glyph.dart';
import 'status_row.dart';

class SectionSpec {
  const SectionSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
    this.glyph,
  });

  final String id;
  final String title;
  final String subtitle;

  /// The Material fallback, used when [glyph] is null. Sections keep one:
  /// `docs/glyph-adoption-spec.md` deliberately does not cover every section,
  /// and "Gym and pool" has no custom glyph.
  final IconData icon;

  /// The custom section glyph, where one exists. Section identity is exactly
  /// what these are for.
  final GlyphKind? glyph;

  final WidgetBuilder builder;
}

class SectionScaffold extends StatefulWidget {
  const SectionScaffold({
    super.key,
    required this.sections,
    this.navWidth = 330,
    this.twoPaneFrom = 900,
  });

  final List<SectionSpec> sections;
  final double navWidth;
  final double twoPaneFrom;

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
            onSelect: (s) => setState(() => _selected = s.id),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
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
  });

  final List<SectionSpec> sections;
  final String? selected;
  final ValueChanged<SectionSpec> onSelect;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          for (final section in sections)
            SectionNavRow(
              spec: section,
              active: section.id == selected,
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
  });

  final SectionSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final background = active
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.surfaceContainerHigh;
    final badge =
        active ? scheme.primary : scheme.primary.withValues(alpha: 0.30);
    final iconColor = active ? scheme.onPrimary : scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: StatusRow.gap),
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
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: badge),
                  child: spec.glyph == null
                      ? Icon(spec.icon, size: 21, color: iconColor)
                      : Glyph(spec.glyph!, size: 21, color: iconColor),
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
                        maxLines: 1,
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
    );
  }
}
