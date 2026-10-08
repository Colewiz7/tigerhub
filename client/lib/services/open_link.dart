/// Opens a link, a phone number or a mail address in whatever the platform
/// uses for it, and copies the text instead when nothing can.
///
/// Linux desktop usually has no dialer and often no mail client, so a `tel:`
/// link there fails. Copying keeps the old behaviour as the fallback, which is
/// what every one of these rows did before this existed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Digits and a leading plus only, so "585-475-2853" dials as `tel:5854752853`.
Uri phoneUri(String number) =>
    Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^0-9+]'), ''));

Future<bool> _launch(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Launches [uri]. When that fails, copies [copyText] and says so with a
/// snackbar naming [label].
Future<void> openOrCopy(
  BuildContext context,
  Uri uri, {
  required String label,
  String? copyText,
}) async {
  if (await _launch(uri)) return;
  await Clipboard.setData(ClipboardData(text: copyText ?? uri.toString()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$label copied')));
}
