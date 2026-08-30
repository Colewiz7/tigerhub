/// Events settings: organizer mutes and keyword rules.
library;

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/event_filter.dart';
import '../../services/filter_profiles.dart';
import '../../services/preferences.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_row.dart';

class EventsSection extends StatefulWidget {
  const EventsSection({super.key, required this.events});

  final List<CampusEvent> events;

  @override
  State<EventsSection> createState() => _EventsSectionState();
}

class _EventsSectionState extends State<EventsSection> {
  final _prefs = Preferences.instance;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final facets = organizerFacets(widget.events);
    final text = Theme.of(context).textTheme;
    final muted = _prefs.mutedOrganizers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      children: [
        _SectionHeading(
          title: 'Profile',
          subtitle: 'A preset is a whole taste in one tap. Editing the rules '
              'below forks to Custom, so switching back is always possible.',
        ),
        _ProfilePicker(prefs: _prefs),
        const SizedBox(height: 26),
        _SectionHeading(
          title: 'Organizers',
          subtitle: '${facets.length} organizers, '
              '${muted.length} muted. Mechanical, and it kills most of the noise.',
          action: muted.isEmpty
              ? null
              : TextButton(
                  onPressed: _prefs.clearMutes,
                  child: const Text('Unmute all'),
                ),
        ),
        for (final facet in facets)
          _OrganizerRow(
            facet: facet,
            muted: facet.key != null && muted.contains(facet.key),
            onChanged: facet.key == null
                ? null
                : (value) => _prefs.setMuted(facet.key!, value),
          ),
        const SizedBox(height: 26),
        _SectionHeading(
          title: 'Keyword rules',
          subtitle: 'Matched against the event title. Organizer muting alone '
              'cannot separate a club fair from a free ice cream giveaway when '
              'the same club posts both.',
          action: Switch(
            value: _prefs.keywordRulesEnabled,
            onChanged: _prefs.setKeywordRulesEnabled,
          ),
        ),
        _KeywordEditor(
          title: 'Hide',
          subtitle: 'Events whose title contains any of these are hidden, '
              'but always recoverable behind the hidden count.',
          icon: Icons.visibility_off_rounded,
          values: _prefs.hideKeywords,
          onChanged: _prefs.setHideKeywords,
          enabled: _prefs.keywordRulesEnabled,
        ),
        const SizedBox(height: 14),
        _KeywordEditor(
          title: 'Boost',
          subtitle: 'These sort to the top of their group with an accent marker.',
          icon: Icons.star_rounded,
          values: _prefs.boostKeywords,
          onChanged: _prefs.setBoostKeywords,
          enabled: _prefs.keywordRulesEnabled,
        ),
        const SizedBox(height: 18),
        Text(
          'Nothing is ever removed permanently. Every filtered view shows a '
          'hidden count you can expand, so a thing that moves to a different '
          'organizer is still findable.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.prefs});

  final Preferences prefs;

  @override
  Widget build(BuildContext context) {
    final active = activeProfile(prefs);

    return Column(
      children: [
        for (final profile in builtInProfiles)
          StatusRow(
            icon: profile.icon,
            title: profile.name,
            subtitle: profile.description,
            emphasis:
                active?.id == profile.id ? RowEmphasis.normal : RowEmphasis.dimmed,
            onTap: () => prefs.applyProfile(
              profile.hide,
              profile.boost,
              keywordsEnabled: profile.keywordsEnabled,
            ),
            trailing: active?.id == profile.id
                ? Icon(Icons.check_circle_rounded,
                    color: Theme.of(context).colorScheme.primary)
                : null,
          ),
        if (active == null)
          StatusRow(
            icon: Icons.tune_rounded,
            title: 'Custom',
            subtitle: 'Your own rules, edited below',
            trailing: Icon(Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary),
          ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge?.copyWith(fontSize: 21)),
                const SizedBox(height: 4),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

class _OrganizerRow extends StatelessWidget {
  const _OrganizerRow({
    required this.facet,
    required this.muted,
    required this.onChanged,
  });

  final OrganizerFacet facet;
  final bool muted;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => StatusRow(
        icon: muted ? Icons.notifications_off_rounded : Icons.groups_rounded,
        title: facet.name,
        subtitle: '${facet.count} event${facet.count == 1 ? '' : 's'}'
            '${facet.key == null ? '' : ' - ${facet.key}'}',
        emphasis: muted ? RowEmphasis.dimmed : RowEmphasis.normal,
        onTap: onChanged == null ? null : () => onChanged!(!muted),
        trailing: Switch(
          value: !muted,
          onChanged: onChanged == null ? null : (on) => onChanged!(!on),
        ),
      );
}

class _KeywordEditor extends StatefulWidget {
  const _KeywordEditor({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.values,
    required this.onChanged,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  State<_KeywordEditor> createState() => _KeywordEditorState();
}

class _KeywordEditorState extends State<_KeywordEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onChanged([...widget.values, value]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Opacity(
      opacity: widget.enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 18, color: scheme.primary),
                const SizedBox(width: 9),
                Text(widget.title.toUpperCase(), style: text.labelSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(widget.subtitle, style: text.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final value in widget.values)
                  Chip(
                    label: Text(value),
                    onDeleted: widget.enabled
                        ? () => widget.onChanged(
                            widget.values.where((v) => v != value).toList())
                        : null,
                    shape: const StadiumBorder(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    decoration: InputDecoration(hintText: 'Add a ${widget.title.toLowerCase()} keyword'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: widget.enabled ? _add : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
