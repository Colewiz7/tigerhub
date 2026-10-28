/// A tab's large title, the way iOS heads a screen.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';

/// A 24 glyph in a 48 hit region, for the gear and Close.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
  });

  final AppIconKind icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Spoken name, when it says more than the tooltip.
  final String? label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: label ?? tooltip,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 48,
          child: Icon(icon.of(context), size: 24, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ),
  );
}

class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key});

  // hig large title size
  static const double fontSize = 34;

  final String text;

  @override
  Widget build(BuildContext context) {
    final phone = Insets.phone(context);
    return Padding(
      padding: phone
          ? const EdgeInsets.fromLTRB(Insets.phoneMargin, 6, Insets.phoneMargin, 6)
          : const EdgeInsets.fromLTRB(26, 20, 26, 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: fontSize, height: 1.15),
          ),
        ),
      ),
    );
  }
}
