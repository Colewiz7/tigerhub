/// The shared card chrome: a section rule, a serif heading, and the quiet
/// freshness line underneath. Every home screen card uses this so the
/// newspaper hierarchy stays consistent.
library;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import 'freshness.dart';

class CardShell extends StatelessWidget {
  const CardShell({
    super.key,
    required this.title,
    required this.child,
    this.state = DataState.ok,
    this.fetchedAt,
    this.trailing,
    this.dragHandle,
  });

  final String title;
  final Widget child;
  final DataState state;
  final DateTime? fetchedAt;
  final Widget? trailing;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: text.titleLarge)),
                ?trailing,
                ?dragHandle,
              ],
            ),
            FreshnessLine(state: state, fetchedAt: fetchedAt),
            const SizedBox(height: 10),
            // The thick rule under a masthead heading.
            Container(height: 2, color: AppTheme.ruleOf(context)),
            const SizedBox(height: 12),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// A single row inside a card, separated by a hairline rule.
class RuledRow extends StatelessWidget {
  const RuledRow({super.key, required this.child, this.last = false});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: child),
          if (!last) Container(height: 1, color: AppTheme.ruleOf(context)),
        ],
      );
}
