/// Housing mailing address card.
///
/// RIT runs a zone based mail system: pick an area, get that area's post
/// office address, with line 2 being your own building and room. There are no
/// mailbox numbers. When the unit is blank the API returns the documented
/// format as a placeholder rather than inventing one.
///
/// A caution badge is shown whenever the API reports `verified: false`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';

class HousingCard extends StatefulWidget {
  const HousingCard({
    super.key,
    required this.areas,
    required this.api,
    this.dragHandle,
  });

  final Result<Collection<HousingArea>> areas;
  final ApiClient api;
  final Widget? dragHandle;

  @override
  State<HousingCard> createState() => _HousingCardState();
}

class _HousingCardState extends State<HousingCard> {
  String? _areaId;
  final _unit = TextEditingController();
  Result<MailingAddress>? _address;

  @override
  void dispose() {
    _unit.dispose();
    super.dispose();
  }

  void _load() {
    final areaId = _areaId;
    if (areaId == null) return;
    widget.api.address(areaId, 'Your Name', _unit.text.trim()).listen((result) {
      if (mounted) setState(() => _address = result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = widget.areas.value?.data ?? const <HousingArea>[];
    final text = Theme.of(context).textTheme;

    return CardShell(
      title: 'Mailing Address',
      state: widget.areas.state,
      fetchedAt: widget.areas.fetchedAt,
      dragHandle: widget.dragHandle,
      child: switch ((widget.areas.isPriming, areas.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading housing areas'),
        (_, true) => const EmptyNote(text: 'No housing areas cached yet.'),
        _ => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _areaId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Where do you live',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final area in areas)
                    DropdownMenuItem(value: area.id, child: Text(area.name)),
                ],
                onChanged: (value) {
                  setState(() {
                    _areaId = value;
                    _address = null;
                  });
                  _load();
                },
              ),
              if (_areaId != null) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _unit,
                  decoration: InputDecoration(
                    labelText: 'Your building and room',
                    hintText: _hintFor(areas),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                  onChanged: (_) => _load(),
                ),
              ],
              if (_address != null) ...[
                const SizedBox(height: 12),
                _AddressBlock(result: _address!),
              ],
              if (_areaId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Pick your housing area to see the correct address format.',
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
      },
    );
  }

  String? _hintFor(List<HousingArea> areas) {
    for (final area in areas) {
      if (area.id == _areaId) return area.line2Example;
    }
    return null;
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.result});

  final Result<MailingAddress> result;

  @override
  Widget build(BuildContext context) {
    final address = result.value;
    if (address == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.ruleOf(context)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in address.lines)
                Text(line, style: text.bodyMedium?.copyWith(height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: address.lines.join('\n')),
              ),
              icon: const Icon(Icons.copy_outlined, size: 15),
              label: const Text('Copy'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
            const Spacer(),
            if (!address.verified) const _CautionBadge(),
          ],
        ),
        if (!address.unitSupplied)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Line 2 shows the format. Enter your own building and room above.',
              style: text.bodySmall,
            ),
          ),
        if (address.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(address.note!, style: text.bodySmall),
          ),
      ],
    );
  }
}

class _CautionBadge extends StatelessWidget {
  const _CautionBadge();

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.warningOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          'unverified',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
