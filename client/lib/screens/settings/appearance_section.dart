/// Appearance: which colour scheme the app uses.
library;

import 'package:flutter/material.dart';

import '../../theme/dynamic_theme.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/status_row.dart';
import '../../widgets/tab_bar.dart';

class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key, required this.scheme});

  final SchemeController scheme;

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  @override
  void initState() {
    super.initState();
    widget.scheme.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.scheme.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(4, 6, 4, 24)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text('Theme', style: text.titleLarge?.copyWith(fontSize: 21)),
        ),
        for (final option in AppScheme.values)
          StatusRow(
            icon: AppIconKind.appearance,
            title: option.label,
            emphasis: option == widget.scheme.choice ? RowEmphasis.normal : RowEmphasis.dimmed,
            onTap: () => widget.scheme.select(option),
            trailing: option == widget.scheme.choice
                ? Icon(AppIconKind.checkCircle.of(context), color: scheme.primary)
                : null,
          ),
      ],
    );
  }
}
