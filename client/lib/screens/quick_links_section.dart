import 'package:flutter/material.dart';

import '../data/quick_links.dart';
import '../services/open_link.dart';
import '../widgets/app_icon.dart';
import '../widgets/status_row.dart';
import '../widgets/tab_bar.dart';

class QuickLinksSection extends StatelessWidget {
  const QuickLinksSection({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(4, 6, 4, 24)),
    children: [
      for (final link in quickLinks)
        StatusRow(
          key: ValueKey(link.label),
          icon: AppIconKind.link,
          title: link.label,
          subtitle: link.subtitle ?? Uri.parse(link.url).host,
          semanticHint: 'Opens externally',
          onTap: () => openOrCopy(context, Uri.parse(link.url), label: link.label),
        ),
    ],
  );
}
