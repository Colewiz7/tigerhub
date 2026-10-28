/// A tab's large title, the way iOS heads a screen.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
