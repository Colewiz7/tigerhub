import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/api_models.dart';
import 'status_row.dart';

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
      .replaceAll('&mdash;', '—');
  value = value.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) => String.fromCharCode(int.parse(match.group(1)!)),
  );
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

  String get _when {
    final date = DateFormat('EEEE, MMMM d');
    final clock = DateFormat('h:mm a');
    if (event.allDay) return '${date.format(event.startsAt)} · All day';
    final start =
        '${date.format(event.startsAt)} · ${clock.format(event.startsAt)}';
    final end = event.endsAt;
    if (end == null) return start;
    final sameDay =
        end.year == event.startsAt.year &&
        end.month == event.startsAt.month &&
        end.day == event.startsAt.day;
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
              icon: Icons.schedule_rounded,
              title: 'When',
              subtitle: _when,
            ),
            if (event.location?.isNotEmpty == true)
              StatusRow(
                icon: Icons.location_on_rounded,
                title: 'Where',
                subtitle: event.location,
                trailing: const Icon(Icons.content_copy_rounded, size: 18),
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
                    onPressed: () => _copy(context, event.url!, 'Event link'),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Copy event link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(
                      context,
                      eventShareText(event, _when),
                      'Event details',
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
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
                  icon: const Icon(Icons.ios_share_rounded),
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
