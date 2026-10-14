/// Copies text, then says so with a snackbar and a screen reader announcement.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

const copiedMessage = 'Copied';

Future<void> copyWithFeedback(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(copiedMessage),
        duration: Duration(seconds: 2),
      ),
    );
  await SemanticsService.sendAnnouncement(
    View.of(context),
    copiedMessage,
    Directionality.of(context),
  );
}
