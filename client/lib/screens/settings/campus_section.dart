/// Campus settings: which post offices show, and putting the layout back.
library;

import 'package:flutter/material.dart';

import '../../data/campus_layout.dart';
import '../../services/clipboard.dart';
import '../../services/preferences.dart';
import '../../widgets/settings_pills.dart';
import '../../widgets/tab_bar.dart';

class CampusSection extends StatefulWidget {
  const CampusSection({super.key});

  @override
  State<CampusSection> createState() => _CampusSectionState();
}

class _CampusSectionState extends State<CampusSection> {
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

  void _setOffices(bool all) => _prefs.setCampusLayout(_prefs.campusLayout.withAllOffices(all));

  void _reset() {
    final before = _prefs.campusLayout;
    showFeedback(context, 'Campus reset', action: SnackBarAction(label: 'Undo', onPressed: () => _prefs.setCampusLayout(before)));
    _prefs.resetCampus();
  }

  void _unhideAll() {
    final before = _prefs.campusLayout;
    showFeedback(
      context,
      'Rows unhidden',
      action: SnackBarAction(
        label: 'Undo',
        // keep what changed since, and hide again only what was hidden
        onPressed: () {
          final now = _prefs.campusLayout;
          _prefs.setCampusLayout(
            CampusLayout(
              order: now.order,
              hidden: {...now.hidden, ...before.hidden},
              hiddenOffices: {...now.hiddenOffices, ...before.hiddenOffices},
              hiddenFacilities: {...now.hiddenFacilities, ...before.hiddenFacilities},
              allOffices: now.allOffices,
              safetyAsked: now.safetyAsked,
            ),
          );
        },
      ),
    );
    _prefs.setCampusLayout(before.unhideAll());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final layout = _prefs.campusLayout;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(4, 6, 4, 24)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text('Post offices', style: text.titleLarge?.copyWith(fontSize: 21)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SettingsChoice(label: 'My side', selected: !layout.allOffices, onTap: () => _setOffices(false)),
            SettingsChoice(label: 'All', selected: layout.allOffices, onTap: () => _setOffices(true)),
          ],
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Layout', style: text.titleLarge?.copyWith(fontSize: 21)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SettingsAction(label: 'Reset Campus', enabled: !layout.isEmpty, onTap: _reset),
            SettingsAction(label: 'Unhide all', enabled: layout.hasHidden, onTap: _unhideAll),
          ],
        ),
      ],
    );
  }
}
