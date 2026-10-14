import 'package:flutter/material.dart';

import '../data/quick_links.dart';
import '../services/open_link.dart';
import '../widgets/status_row.dart';

class QuickLinksSection extends StatelessWidget {
  const QuickLinksSection({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('Open in your browser', style: Theme.of(context).textTheme.titleLarge),
      ),
      for (final link in quickLinks)
        StatusRow(
          key: ValueKey(link.label),
          icon: Icons.open_in_new_rounded,
          title: link.label,
          subtitle: Uri.parse(link.url).host,
          semanticHint: 'Opens externally',
          onTap: () => openOrCopy(context, Uri.parse(link.url), label: link.label),
        ),
    ],
  );
}
