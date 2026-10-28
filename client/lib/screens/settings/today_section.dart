/// Today settings: smart order.
library;

import 'package:flutter/material.dart';

import '../../services/preferences.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/status_row.dart';
import '../../widgets/tab_bar.dart';

class TodaySection extends StatelessWidget {
  const TodaySection({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = Preferences.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(4, 6, 4, 24)),
        children: [
          StatusRow(
            icon: AppIconKind.tune,
            title: 'Smart order',
            subtitle: 'Eat now rises at meal times, Up next an hour before an event',
            subtitleMaxLines: null,
            onTap: () => prefs.setTodaySmartOrder(!prefs.todaySmartOrder),
            trailing: Switch(
              value: prefs.todaySmartOrder,
              onChanged: prefs.setTodaySmartOrder,
            ),
          ),
        ],
      ),
    );
  }
}
