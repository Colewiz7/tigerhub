/// Home screen: which cards are visible.
///
/// Ordering itself is done by dragging on the Today tab, since that is where
/// the cards are. This is the on and off switch.
library;

import 'package:flutter/material.dart';

import '../../widgets/status_row.dart';

const Map<String, ({String label, String detail, IconData icon})> homeCards = {
  'dining': (
    label: 'Dining',
    detail: 'Open now, hours, occupancy',
    icon: Icons.restaurant_rounded,
  ),
  'events': (
    label: 'Events',
    detail: 'Grouped by organizer',
    icon: Icons.event_note_rounded,
  ),
  'chefs': (
    label: 'Visiting Chefs',
    detail: "Today's visiting chefs",
    icon: Icons.restaurant_menu_rounded,
  ),
  'housing': (
    label: 'Mailing Address',
    detail: 'Your campus mail format',
    icon: Icons.markunread_mailbox_rounded,
  ),
};

class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.cards,
    required this.hidden,
    required this.onChanged,
  });

  final List<String> cards;
  final List<String> hidden;
  final void Function(List<String> order, List<String> hidden) onChanged;

  void _toggle(String id, bool visible) {
    if (visible) {
      onChanged([...cards, id], hidden.where((c) => c != id).toList());
    } else {
      onChanged(cards.where((c) => c != id).toList(), [...hidden, id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cards', style: text.titleLarge?.copyWith(fontSize: 21)),
              const SizedBox(height: 4),
              Text(
                'Drag a card on the Today tab to reorder it. '
                'Current order: ${cards.map((c) => homeCards[c]?.label ?? c).join(', ')}.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        for (final entry in homeCards.entries)
          Builder(builder: (context) {
            final visible = cards.contains(entry.key);
            return StatusRow(
              icon: entry.value.icon,
              title: entry.value.label,
              subtitle: entry.value.detail,
              emphasis: visible ? RowEmphasis.normal : RowEmphasis.dimmed,
              onTap: () => _toggle(entry.key, !visible),
              trailing: Switch(
                value: visible,
                onChanged: (on) => _toggle(entry.key, on),
              ),
            );
          }),
      ],
    );
  }
}
