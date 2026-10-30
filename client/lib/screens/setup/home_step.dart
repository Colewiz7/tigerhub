/// Step 3: where you live. The area, then a room if the area takes one.
library;

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/empty_state.dart';
import 'setup_kit.dart';

class HomeStep extends StatefulWidget {
  const HomeStep({super.key});

  @override
  State<HomeStep> createState() => _HomeStepState();
}

class _HomeStepState extends State<HomeStep> {
  TextEditingController? _unit;

  @override
  void dispose() {
    _unit?.dispose();
    super.dispose();
  }

  HousingArea? _selected(SetupFlowController flow) {
    for (final area in flow.areas) {
      if (area.id == flow.draft.area) return area;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    final text = Theme.of(context).textTheme;
    // seeded once, from the draft, and never autofocused
    _unit ??= TextEditingController(text: flow.draft.unit ?? '');

    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final selected = _selected(flow);
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.housing),
          title: 'Where you live',
          subtitle: 'For your mailing address and shuttle times.',
          leading: flow.leadingFor(context, SetupStep.home),
          trailing: flow.trailingFor(context),
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                if (flow.areas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(kind: EmptyKind.sourceDown, title: 'Housing unavailable'),
                  )
                else
                  SetupGroup(
                    children: [
                      for (final area in flow.areas)
                        SetupRow(
                          title: area.name,
                          selected: area.id == flow.draft.area,
                          trailing: SetupCheck(shown: area.id == flow.draft.area),
                          onTap: () {
                            setupSelect();
                            flow.draft.setArea(area.id);
                          },
                        ),
                    ],
                  ),
                if (selected != null && !selected.directDelivery)
                  SetupGroup(
                    header: 'Building and room, optional',
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _unit,
                            textInputAction: TextInputAction.done,
                            style: text.bodyMedium,
                            onChanged: flow.draft.setUnit,
                            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: InputDecoration(
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              hintText: selected.line2Example ?? 'Building and room',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (selected != null && selected.directDelivery)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Mail goes straight to the property here, not through a campus post office.',
                      style: text.bodySmall,
                    ),
                  ),
              ]),
            ),
          ],
          primary: setupPrimaryLabel(chosen: flow.draft.hasHome),
          onPrimary: () {
            FocusManager.instance.primaryFocus?.unfocus();
            flow.next(context, SetupStep.home);
          },
        );
      },
    );
  }
}
