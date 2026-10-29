/// Rows in one rounded container with hairlines between, and a plain title.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'status_row.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class InsetGroup extends StatelessWidget {
  const InsetGroup({super.key, required this.children});

  // StatusRows built with grouped: true
  final List<Widget> children;

  // badge plus the gap after it, plus the row's own inset
  static const double separatorInset = 12 + StatusRow.badgeSize + 13;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: Shapes.inner),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: separatorInset),
                  child: SizedBox(height: hairline, width: double.infinity, child: ColoredBox(color: scheme.outlineVariant)),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
