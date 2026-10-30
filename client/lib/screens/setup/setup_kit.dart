/// The pieces every setup screen shares: the page, the flow's controller and
/// the grouped list.
///
/// One page layout so the seven steps read as one thing: a scalloped badge,
/// a large title, one sentence, then the choices, with a single capsule button
/// pinned above the safe area. The page scrolls and the button does not, so at
/// large text nothing is cut off and the way on is always in the same place.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/api_models.dart';
import '../../motion/reduce_motion.dart';
import '../../services/dashboard.dart';
import '../../services/preferences.dart';
import '../../services/setup_draft.dart';
import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focus_ring.dart';

enum SetupStep { welcome, look, home, spots, events, today, done }

const double setupSideMargin = 20;
const double setupMaxWidth = 560;
const double setupButtonHeight = 50;

/// The label the one primary button wears: Continue once something is chosen,
/// Set up later when nothing is.
String setupPrimaryLabel({required bool chosen}) => chosen ? 'Continue' : 'Set up later';

/// A selection click on every pick and toggle.
void setupSelect() => HapticFeedback.selectionClick();

/// A native push on iOS, with the edge swipe back. Reduce Motion crossfades.
Route<T> setupRoute<T>(BuildContext context, WidgetBuilder builder) {
  if (reduceMotion(context)) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 240),
    );
  }
  return defaultTargetPlatform == TargetPlatform.iOS
      ? CupertinoPageRoute<T>(builder: builder)
      : MaterialPageRoute<T>(builder: builder);
}

/// What the steps share. Holds the draft and moves between the steps.
class SetupFlowController extends ChangeNotifier {
  SetupFlowController({
    required this.scheme,
    required this.areas,
    required this.dining,
    required this.events,
    required this.dashboard,
    required this.rerun,
    required this.onDone,
    required this.buildStep,
    this.onCancel,
    Preferences? prefs,
  }) : prefs = prefs ?? Preferences.instance,
       initialScheme = scheme.choice,
       steps = [
         if (!rerun) SetupStep.welcome,
         SetupStep.look,
         SetupStep.home,
         SetupStep.spots,
         SetupStep.events,
         SetupStep.today,
         SetupStep.done,
       ] {
    draft = rerun
        ? SetupDraft.prefilled(prefs: this.prefs, scheme: scheme.choice, dashboard: dashboard)
        : SetupDraft();
  }

  final SchemeController scheme;
  List<HousingArea> areas;
  List<DiningLocation> dining;
  List<CampusEvent> events;
  final List<CardInstance> dashboard;
  final bool rerun;

  /// The feeds can land after setup opens, so the steps follow them.
  void setData({required List<HousingArea> areas, required List<DiningLocation> dining, required List<CampusEvent> events}) {
    if (identical(this.areas, areas) && identical(this.dining, dining) && identical(this.events, events)) return;
    this.areas = areas;
    this.dining = dining;
    this.events = events;
    // called while the tree is building, so the steps hear about it after
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;
  bool _applied = false;

  @override
  void dispose() {
    _disposed = true;
    // left without applying, so an unsaved look does not outlive the flow
    if (!_applied) {
      scheduleMicrotask(() {
        if (!scheme.disposed) scheme.clearPreview();
      });
    }
    super.dispose();
  }

  final Preferences prefs;

  /// Setup is answered and the app can show.
  final VoidCallback onDone;

  /// A re-run was cancelled.
  final VoidCallback? onCancel;

  final Widget Function(SetupStep) buildStep;
  final AppScheme initialScheme;
  final List<SetupStep> steps;
  late final SetupDraft draft;

  /// The route the flow starts on, which finishing pops back to.
  Route<dynamic>? base;

  /// The scheme previews live and is only saved when the flow is applied.
  void chooseScheme(AppScheme value) {
    draft.setScheme(value);
    scheme.preview(value);
  }

  Widget wrap(Widget child) => SetupScope(
    controller: this,
    child: ListenableBuilder(
      listenable: scheme,
      builder: (context, _) => AnimatedTheme(
        // the platform stays the host's, so iOS keeps its glyphs
        data: AppTheme.from(scheme.scheme).copyWith(platform: Theme.of(context).platform),
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 240),
        child: child,
      ),
    ),
  );

  /// The step after [from], or the end when there is none.
  void next(BuildContext context, SetupStep from) {
    final at = steps.indexOf(from);
    if (at + 1 >= steps.length) {
      finish(context);
      return;
    }
    Navigator.of(context).push(setupRoute<void>(context, (_) => wrap(buildStep(steps[at + 1]))));
  }

  /// Top left of a step: Cancel on a re-run's first step.
  Widget? leadingFor(BuildContext context, SetupStep step) =>
      rerun && step == steps.first ? SetupTextAction(label: 'Cancel', onTap: () => cancel(context)) : null;

  /// Top right of a step: Save, on a re-run.
  Widget? trailingFor(BuildContext context) =>
      rerun ? SetupTextAction(label: 'Save', onTap: () => finish(context)) : null;

  Future<void> finish(BuildContext context) async {
    final navigator = Navigator.of(context);
    _applied = true;
    await applyDraft(draft, prefs: prefs, scheme: scheme);
    navigator.popUntil((route) => route == base || route.isFirst);
    onDone();
  }

  /// Welcome's Use defaults: answered, nothing changed, a tried look dropped.
  Future<void> useDefaults() async {
    scheme.clearPreview();
    await prefs.markSetupSeen();
    onDone();
  }

  /// A re-run backs out and the scheme goes back to what it was.
  Future<void> cancel(BuildContext context) async {
    final navigator = Navigator.of(context);
    scheme.clearPreview();
    navigator.popUntil((route) => route == base || route.isFirst);
    onCancel?.call();
  }
}

class SetupScope extends InheritedNotifier<SetupFlowController> {
  const SetupScope({super.key, required SetupFlowController controller, required super.child}) : super(notifier: controller);

  static SetupFlowController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SetupScope>();
    assert(scope != null, 'no setup flow above this context');
    return scope!.notifier!;
  }
}

/// A scalloped badge carrying the step's glyph.
class SetupBadge extends StatelessWidget {
  const SetupBadge({super.key, required this.glyph, this.size = 64});

  final AppIconKind glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Material(
          elevation: 0,
          color: scheme.primary,
          shape: Shapes.badge,
          child: Center(child: AppIcon(glyph, size: size * 0.5, color: scheme.onPrimary)),
        ),
      ),
    );
  }
}

/// The back chevron. Cancel stands in for it on a re-run's first step.
class SetupBackButton extends StatelessWidget {
  const SetupBackButton({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Back',
    child: Semantics(
      button: true,
      label: 'Back',
      excludeSemantics: true,
      child: FocusRing(
        radius: 24,
        builder: (onFocusChange) => InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          onFocusChange: onFocusChange,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 48,
            child: Icon(AppIconKind.back.of(context), size: 24, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    ),
  );
}

class SetupTextAction extends StatelessWidget {
  const SetupTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FocusRing(
    radius: 24,
    builder: (onFocusChange) => TextButton(
      onPressed: onTap,
      onFocusChange: onFocusChange,
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
      child: Text(label),
    ),
  );
}

class SetupPage extends StatelessWidget {
  const SetupPage({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.slivers = const [],
    this.afterHeader,
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// The glyph or mascot above the title.
  final Widget? badge;

  /// Sits between the subtitle and the slivers, for a preview.
  final Widget? afterHeader;
  final List<Widget> slivers;

  final String primary;
  final VoidCallback onPrimary;

  /// The plain text button under the capsule.
  final String? secondary;
  final VoidCallback? onSecondary;

  /// Top left. The back chevron when absent and there is somewhere to go back to.
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canGoBack = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    leading ?? (canGoBack ? const SetupBackButton() : const SizedBox(width: 48)),
                    const Spacer(),
                    ?trailing,
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = ((constraints.maxWidth - setupMaxWidth) / 2).clamp(setupSideMargin, double.infinity);
                  return CustomScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 8, side, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            if (badge != null) Align(alignment: AlignmentDirectional.centerStart, child: badge),
                            if (badge != null) const SizedBox(height: 16),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: text.titleLarge?.copyWith(
                                  fontSize: 34,
                                  height: 1.15,
                                  fontWeight: AppTheme.weight(Weights.bold),
                                  fontVariations: Weights.bold,
                                ),
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                subtitle!,
                                style: text.bodyMedium?.copyWith(fontSize: 17, color: scheme.onSurfaceVariant),
                              ),
                            ],
                            if (afterHeader != null) ...[const SizedBox(height: 20), afterHeader!],
                            const SizedBox(height: 24),
                          ]),
                        ),
                      ),
                      for (final sliver in slivers)
                        SliverPadding(padding: EdgeInsets.symmetric(horizontal: side), sliver: sliver),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  );
                },
              ),
            ),
            _PinnedButtons(primary: primary, onPrimary: onPrimary, secondary: secondary, onSecondary: onSecondary),
          ],
        ),
      ),
    );
  }
}

class _PinnedButtons extends StatelessWidget {
  const _PinnedButtons({required this.primary, required this.onPrimary, this.secondary, this.onSecondary});

  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - setupMaxWidth) / 2).clamp(setupSideMargin, double.infinity);
        return Padding(
          padding: EdgeInsets.fromLTRB(side, 8, side, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FocusRing(
                radius: setupButtonHeight / 2,
                builder: (onFocusChange) => SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPrimary,
                    onFocusChange: onFocusChange,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(setupButtonHeight),
                      shape: const StadiumBorder(),
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                    child: Text(primary, textAlign: TextAlign.center),
                  ),
                ),
              ),
              if (secondary != null)
                SetupTextAction(label: secondary!, onTap: onSecondary ?? () {})
              else
                const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Rows in one rounded container with hairlines between, the way iOS groups a
/// settings list.
class SetupGroup extends StatelessWidget {
  const SetupGroup({super.key, required this.children, this.header, this.footer});

  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Semantics(
                header: true,
                child: Text(header!, style: text.bodySmall?.copyWith(fontSize: 14, color: scheme.onSurfaceVariant)),
              ),
            ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: Shapes.inner),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16),
                      child: SizedBox(height: hairline, width: double.infinity, child: ColoredBox(color: scheme.outlineVariant)),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(footer!, style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// A row in a [SetupGroup]: a title, an optional line under it, something at
/// the end, and a 48pt target when it can be tapped.
class SetupRow extends StatelessWidget {
  const SetupRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected,
    this.semanticsLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Non-null makes the row a radio or a toggle for assistive tech.
  final bool? selected;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: text.bodyMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      onTap: onTap,
      child: FocusRing(
        radius: Shapes.innerRadius,
        builder: (onFocusChange) => InkWell(onTap: onTap, onFocusChange: onFocusChange, child: row),
      ),
    );
  }
}

/// A trailing check for the chosen row.
class SetupCheck extends StatelessWidget {
  const SetupCheck({super.key, required this.shown});

  final bool shown;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: shown ? AppIcon(AppIconKind.check, size: 22, color: Theme.of(context).colorScheme.primary) : null,
  );
}
