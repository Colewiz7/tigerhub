/// Housing mailing address.
///
/// The address block is the hero. RIT runs a zone based mail system: pick an
/// area, get that area's post office address, with line 2 being your own
/// building and room. There are no mailbox numbers. When the unit is blank the
/// API returns the documented format as a placeholder rather than inventing
/// one.
///
/// A caution pill appears whenever the API reports verified: false.
library;

import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/preferences.dart';
import '../theme/tokens.dart';
import '../widgets/card_shell.dart';
import '../widgets/glyph.dart';
import '../widgets/copyable_address.dart';
import '../widgets/freshness.dart';
import '../services/subscriptions.dart';

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

  /// Held so they can be cancelled. Dangling subscriptions let a previous
  /// visit's results land after the current ones and overwrite them.
  final _subscriptions = Subscriptions();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Default to whatever was picked last. Re-choosing your own dorm every time
  /// is the kind of small friction that makes a lookup not worth opening.
  Future<void> _restore() async {
    final prefs = Preferences.instance;
    if (!prefs.loaded) await prefs.load();
    final area = prefs.homeArea;
    if (!mounted || area == null) return;
    setState(() {
      _areaId = area;
      if (prefs.homeUnit.isNotEmpty) _unit.text = prefs.homeUnit;
    });
    _load();
  }

  /// Writes through Preferences rather than straight to the cache, so first
  /// run setup and this card cannot drift apart. They are the same setting: it
  /// is where you live, not a property of one card.
  Future<void> _remember() async {
    await Preferences.instance.setHome(
      area: _areaId,
      unit: _unit.text.trim(),
    );
  }

  @override
  void dispose() {
    _subscriptions.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _load() {
    final areaId = _areaId;
    if (areaId == null) return;
    _subscriptions.add(widget.api.address(areaId, 'Your Name', _unit.text.trim()).listen((result) {
      if (mounted) setState(() => _address = result);
    }));
    _remember();
  }

  @override
  Widget build(BuildContext context) {
    final areas = widget.areas.value?.data ?? const <HousingArea>[];

    return CardShell(
      glyph: GlyphKind.housing,
      title: 'Mailing Address',
      state: widget.areas.state,
      fetchedAt: widget.areas.fetchedAt,
      dragHandle: widget.dragHandle,
      child: switch ((widget.areas.isPriming, areas.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading housing areas'),
        (_, true) => const EmptyState(
            kind: EmptyKind.sourceDown,
            title: 'Housing areas are unavailable',
          ),
        // Never an empty card: it is either the picker or the answer.
        (_, _) when _address?.value == null => _AreaChips(
            areas: areas,
            onPick: (id) {
              setState(() => _areaId = id);
              _load();
            },
          ),
        _ => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _AreaPicker(
                  areas: areas,
                  selected: _areaId,
                  onChanged: (value) {
                    setState(() {
                      _areaId = value;
                      _address = null;
                    });
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                _AddressBlock(address: _address!.value!),
              ],
            ),
          ),
      },
    );
  }
}

/// The empty state, which fills the card rather than leaving it blank. Every
/// area is one tap away, which is faster than opening a menu anyway.
class _AreaChips extends StatelessWidget {
  const _AreaChips({required this.areas, required this.onPick});

  final List<HousingArea> areas;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('WHERE DO YOU LIVE', style: text.labelSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final area in areas)
              Material(
                elevation: 0,
                color: scheme.surfaceContainerHigh,
                shape: Shapes.pill,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onPick(area.id),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                    child: Text(area.name, style: text.bodyMedium),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Split control: a wide pill for the value, a separate small pill holding the
/// chevron.
class _AreaPicker extends StatelessWidget {
  const _AreaPicker({
    required this.areas,
    required this.selected,
    required this.onChanged,
  });

  final List<HousingArea> areas;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = areas.where((a) => a.id == selected).firstOrNull;

    return Row(
      children: [
        Expanded(
          child: Material(
            elevation: 0,
            color: scheme.surfaceContainerHigh,
            shape: Shapes.pill,
            clipBehavior: Clip.antiAlias,
            child: PopupMenuButton<String>(
              tooltip: 'Choose housing area',
              onSelected: onChanged,
              itemBuilder: (context) => [
                for (final area in areas)
                  PopupMenuItem(value: area.id, child: Text(area.name)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  current?.name ?? 'Where do you live',
                  style: text.bodyMedium?.copyWith(
                    color: current == null ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Material(
          elevation: 0,
          color: scheme.primary,
          shape: Shapes.pill,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(
              Icons.expand_more_rounded,
              size: 19,
              color: scheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.address});

  final MailingAddress address;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The hero: nested one surface level lighter than the card.
        //
        // Every line copies on its own, because web order forms want street,
        // city, state and ZIP in separate fields.
        CopyableAddress(
          lines: address.lines,
          trailing: address.verified ? null : const _CautionPill(),
        ),
        if (!address.unitSupplied)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Line 2 shows the format. Yours goes there.',
              style: text.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _CautionPill extends StatelessWidget {
  const _CautionPill();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: scheme.errorContainer,
      shape: Shapes.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 13, color: scheme.onErrorContainer),
            const SizedBox(width: 5),
            Text(
              'unverified',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
