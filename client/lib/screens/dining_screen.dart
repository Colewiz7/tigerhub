/// Dining tab: every location, grouped by category.
///
/// Categories come from the server's static config, because TigerCenter
/// publishes none of its own (catId, mapId and mrkId are 0 on all 24, and
/// department is "Dining" for every one).
library;

import 'package:flutter/material.dart';

import '../cards/dining_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/jump_list.dart';
import '../widgets/freshness.dart';
import '../services/preferences.dart';
import '../widgets/status_row.dart';

class DiningScreen extends StatefulWidget {
  const DiningScreen({super.key, required this.result, required this.api});

  final Result<Collection<DiningLocation>> result;
  final ApiClient api;

  @override
  State<DiningScreen> createState() => _DiningScreenState();
}

class _DiningScreenState extends State<DiningScreen> {
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
    if (widget.result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading dining hours');
    }

    final groups = groupByCategory(
      widget.result.value?.data ?? const [],
      pinned: _prefs.pinnedDining,
    );

    return JumpList(
      groups: [
        for (final group in groups)
          JumpGroup(
            label: group.key,
            icon: iconForCategory(group.value.first.category),
            // The rail counts what is open, which is what people are scanning
            // for, not how many exist.
            count: group.value.where((l) => l.isOpen).length,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GroupHeader(
                  icon: iconForCategory(group.value.first.category),
                  title: group.key,
                  count: group.value.where((l) => l.isOpen).length,
                ),
                for (final location in group.value)
                  DiningRow(location: location, api: widget.api),
              ],
            ),
          ),
      ],
    );
  }
}
