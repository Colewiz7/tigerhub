import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/campus_time.dart';
import '../models/api_models.dart';
import '../services/open_link.dart';
import 'app_icon.dart';
import 'status_row.dart';

// &#8212; and &#x2014; with or without the semicolon, as HTML5 allows. Digits
// are consumed greedily, so '&#8212abc' is a dash then 'abc'. A number that is
// not a character (zero, a surrogate, past U+10FFFF) is left as written.
String _decodeNumericEntities(String value) => value.replaceAllMapped(
  RegExp(r'&#(?:[xX]([0-9a-fA-F]+)|([0-9]+));?'),
  (match) {
    final hex = match.group(1);
    final code = hex != null
        ? int.tryParse(hex, radix: 16)
        : int.tryParse(match.group(2)!);
    final valid =
        code != null &&
        code > 0 &&
        code <= 0x10FFFF &&
        !(code >= 0xD800 && code <= 0xDFFF);
    return valid ? String.fromCharCode(code) : match.group(0)!;
  },
);

String eventDescriptionText(String? raw, {String? eventUrl}) {
  if (raw == null || raw.trim().isEmpty) return '';
  var value = raw
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|li|h[1-6])\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', '’')
      .replaceAll('&ndash;', '–')
      .replaceAll('&mdash;', '-');
  value = _decodeNumericEntities(value);
  // numeric entities can still decode to an em dash
  value = value.replaceAll('\u{2014}', '-');
  if (eventUrl != null && eventUrl.isNotEmpty) {
    value = value.replaceAll('Event Details: $eventUrl', '');
  }
  value = value.replaceAll(RegExp(r'\n\s*---\s*\n?'), '\n');
  value = value.replaceAll(RegExp(r'[ \t]+'), ' ');
  value = value.replaceAll(RegExp(r' *\n *'), '\n');
  value = value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return value.trim();
}

Future<void> showEventDetailsSheet(BuildContext context, CampusEvent event) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => _EventDetailsSheet(event: event),
    );

String eventShareText(CampusEvent event, String when) => [
  event.title,
  when,
  if (event.location?.isNotEmpty == true) event.location!,
  if (event.url?.isNotEmpty == true) event.url!,
].join('\n');

class _EventDetailsSheet extends StatelessWidget {
  const _EventDetailsSheet({required this.event});

  final CampusEvent event;

  /// Campus clock, not device clock: see `formatClock`.
  String get _when {
    final date = DateFormat('EEEE, MMMM d');
    final clock = DateFormat('h:mm a');
    final from = CampusTime.fieldsOf(event.startsAt);
    if (event.allDay) return '${date.format(from)} · All day';
    final start = '${date.format(from)} · ${clock.format(from)}';
    final end = event.endsAt == null
        ? null
        : CampusTime.fieldsOf(event.endsAt!);
    if (end == null) return start;
    final sameDay =
        end.year == from.year && end.month == from.month && end.day == from.day;
    return sameDay
        ? '$start–${clock.format(end)}'
        : '$start–${date.format(end)} · ${clock.format(end)}';
  }

  Future<void> _copy(BuildContext context, String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final description = eventDescriptionText(
      event.description,
      eventUrl: event.url,
    );

    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          22,
          2,
          22,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.title, style: text.headlineSmall),
            if (event.organizer?.isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(event.organizer!, style: text.titleMedium),
            ],
            const SizedBox(height: 18),
            StatusRow(
              icon: AppIconKind.time,
              title: 'When',
              subtitle: _when,
            ),
            if (event.location?.isNotEmpty == true)
              StatusRow(
                icon: AppIconKind.location,
                title: 'Where',
                subtitle: event.location,
                trailing: Icon(AppIconKind.copy.of(context), size: 18),
                semanticHint: 'Copies the event location',
                onTap: () => _copy(context, event.location!, 'Location'),
              ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('ABOUT', style: text.labelSmall),
              const SizedBox(height: 7),
              SelectableText(description, style: text.bodyMedium),
            ],
            if (event.url?.isNotEmpty == true) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => openOrCopy(
                      context,
                      Uri.parse(event.url!),
                      label: 'Event link',
                    ),
                    icon: Icon(AppIconKind.link.of(context)),
                    label: const Text('Open event page'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(context, event.url!, 'Event link'),
                    icon: Icon(AppIconKind.linkChain.of(context)),
                    label: const Text('Copy event link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(
                      context,
                      eventShareText(event, _when),
                      'Event details',
                    ),
                    icon: Icon(AppIconKind.share.of(context)),
                    label: const Text('Copy event details'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _copy(
                    context,
                    eventShareText(event, _when),
                    'Event details',
                  ),
                  icon: Icon(AppIconKind.share.of(context)),
                  label: const Text('Copy event details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
