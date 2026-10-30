/// Setup: seven short screens, each one question, all optional.
///
/// First run walks all seven. A re-run from Settings skips the welcome, starts
/// from what is stored and ends in Save or Cancel. Either way nothing is
/// written until the end, apart from the colour scheme, which previews live and
/// goes back on Cancel.
///
/// **It does not block the app.** Every step can be passed without choosing,
/// and Use defaults on the first screen is one tap into the app as it ships.
/// It also does not wait on the network: the housing areas are bundled config,
/// and an empty Dining or Events feed is said plainly while setup carries on.
library;

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/dashboard.dart';
import '../../theme/dynamic_theme.dart';
import 'events_step.dart';
import 'home_step.dart';
import 'look_step.dart';
import 'setup_kit.dart';
import 'spots_step.dart';
import 'today_step.dart';
import 'welcome_step.dart';

export 'setup_kit.dart' show SetupStep;

Widget buildSetupStep(SetupStep step) => switch (step) {
  SetupStep.welcome => const WelcomeStep(),
  SetupStep.look => const LookStep(),
  SetupStep.home => const HomeStep(),
  SetupStep.spots => const SpotsStep(),
  SetupStep.events => const EventsStep(),
  SetupStep.today => const TodayStep(),
  _ => const SizedBox.shrink(),
};

class SetupFlow extends StatefulWidget {
  const SetupFlow({
    super.key,
    required this.scheme,
    required this.areas,
    required this.onDone,
    this.dining = const [],
    this.events = const [],
    this.dashboard = defaultDashboard,
    this.rerun = false,
    this.onCancel,
  });

  final SchemeController scheme;
  final List<HousingArea> areas;
  final List<DiningLocation> dining;
  final List<CampusEvent> events;

  /// The cards Today holds now, for a re-run to start from.
  final List<CardInstance> dashboard;
  final bool rerun;

  /// Setup is answered, or a re-run was saved.
  final VoidCallback onDone;
  final VoidCallback? onCancel;

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  late final SetupFlowController _flow = SetupFlowController(
    scheme: widget.scheme,
    areas: widget.areas,
    dining: widget.dining,
    events: widget.events,
    dashboard: widget.dashboard,
    rerun: widget.rerun,
    onDone: widget.onDone,
    onCancel: widget.onCancel,
    buildStep: buildSetupStep,
  );

  @override
  void didUpdateWidget(SetupFlow old) {
    super.didUpdateWidget(old);
    _flow.setData(areas: widget.areas, dining: widget.dining, events: widget.events);
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _flow.base = ModalRoute.of(context);
    final first = _flow.wrap(buildSetupStep(_flow.steps.first));
    if (!widget.rerun) return first;
    // the system back button cancels a re-run, which puts the scheme back
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _flow.cancel(context);
      },
      child: first,
    );
  }
}
