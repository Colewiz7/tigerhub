/// Hide and unhide actions for Campus rows, and the one Safety question.
library;

import 'package:flutter/material.dart';

import '../data/campus_layout.dart';
import '../services/clipboard.dart';
import '../services/preferences.dart';
import 'app_icon.dart';
import 'context_actions.dart';

typedef LayoutEdit = CampusLayout Function(CampusLayout layout);

// the row leaves the list once hidden, so speak first and let Undo bring it back
void hideWithUndo(BuildContext context, {required String name, required LayoutEdit hide, required LayoutEdit show}) {
  final prefs = Preferences.instance;
  showFeedback(
    context,
    'Hid $name',
    action: SnackBarAction(label: 'Undo', onPressed: () => prefs.setCampusLayout(show(prefs.campusLayout))),
  );
  prefs.setCampusLayout(hide(prefs.campusLayout));
}

MenuAction hideAction({required String name, required LayoutEdit hide, required LayoutEdit show}) => MenuAction(
  label: 'Hide',
  icon: AppIconKind.hidden,
  onSelected: (context) => hideWithUndo(context, name: name, hide: hide, show: show),
);

MenuAction unhideAction(LayoutEdit show) => MenuAction(
  label: 'Unhide',
  icon: AppIconKind.hidden,
  onSelected: (_) => Preferences.instance.setCampusLayout(show(Preferences.instance.campusLayout)),
);

// Safety holds the emergency numbers, so the first hide asks
Future<bool> confirmHideSafety(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hide Safety?'),
      content: const Text('It holds the emergency numbers. Bring it back from Hidden.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hide')),
      ],
    ),
  );
  return ok ?? false;
}

// Safety asks once, then hides like any other row
MenuAction hideSectionAction(String id, String name) {
  CampusLayout show(CampusLayout l) => l.showSection(id);
  if (id != safetySectionId) return hideAction(name: name, hide: (l) => l.hideSection(id), show: show);
  return MenuAction(
    label: 'Hide',
    icon: AppIconKind.hidden,
    onSelected: (context) async {
      final asked = Preferences.instance.campusLayout.safetyAsked;
      if (!asked && !await confirmHideSafety(context)) return;
      if (!context.mounted) return;
      hideWithUndo(context, name: name, hide: (l) => l.markSafetyAsked().hideSection(id), show: show);
    },
  );
}
