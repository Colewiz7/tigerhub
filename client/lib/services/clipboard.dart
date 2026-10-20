/// Copies text, then says so with a snackbar and a screen reader announcement.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

const copiedMessage = 'Copied';

// reads the context before any await, so a row that disappears can still speak
Future<void> showFeedback(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final view = View.of(context);
  final direction = Directionality.of(context);
  final accessible = MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
  // an Undo needs time to reach; plain feedback stays short
  final duration = action == null ? const Duration(seconds: 2) : Duration(seconds: accessible ? 10 : 5);
  messenger
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        persist: false,
        action: action,
      ),
    );
  return SemanticsService.sendAnnouncement(view, message, direction);
}

Future<void> copyWithFeedback(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  await showFeedback(context, copiedMessage);
}
