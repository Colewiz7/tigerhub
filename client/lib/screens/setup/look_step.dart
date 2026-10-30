/// Step 2: pick a look. Phone shaped previews side by side, like iOS Appearance.
library;

import 'package:flutter/material.dart';

import '../../motion/reduce_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focus_ring.dart';
import 'mini_today.dart';
import 'setup_kit.dart';

class LookStep extends StatelessWidget {
  const LookStep({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final picked = flow.draft.scheme ?? flow.scheme.choice;
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.appearance),
          title: 'Pick a look',
          subtitle: 'Choose the colours TigerHub uses.',
          leading: flow.leadingFor(context, SetupStep.look),
          trailing: flow.trailingFor(context),
          slivers: [
            SliverToBoxAdapter(
              child: _Previews(picked: picked, onPick: flow.chooseScheme),
            ),
          ],
          primary: setupPrimaryLabel(chosen: flow.draft.scheme != null),
          onPrimary: () => flow.next(context, SetupStep.look),
        );
      },
    );
  }
}

class _Previews extends StatefulWidget {
  const _Previews({required this.picked, required this.onPick});

  final AppScheme picked;
  final ValueChanged<AppScheme> onPick;

  @override
  State<_Previews> createState() => _PreviewsState();
}

class _PreviewsState extends State<_Previews> {
  static const double _gap = 12;

  // opens with the chosen look in view, one before it showing
  late final _scroll = ScrollController(
    initialScrollOffset: (AppScheme.values.indexOf(widget.picked) - 1).clamp(0, AppScheme.values.length) * (_scrollWidth + _gap),
  );

  static const double _scrollWidth = 132;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  AppScheme get picked => widget.picked;
  ValueChanged<AppScheme> get onPick => widget.onPick;

  @override
  Widget build(BuildContext context) {
    final schemes = AppScheme.values;
    // large text needs room for the labels, so the previews widen and scroll
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return LayoutBuilder(
      builder: (context, constraints) {
        // three fit across a phone, more scroll sideways
        final fits = schemes.length <= 3 && !large;
        final width = fits ? (constraints.maxWidth - _gap * (schemes.length - 1)) / schemes.length : (large ? 176.0 : _scrollWidth);
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < schemes.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(
                width: width,
                child: _Preview(scheme: schemes[i], selected: schemes[i] == picked, width: width, onTap: () {
                  setupSelect();
                  onPick(schemes[i]);
                }),
              ),
            ],
          ],
        );
        return fits ? row : SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal, child: row);
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.scheme, required this.selected, required this.width, required this.onTap});

  final AppScheme scheme;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final height = width * 2.05;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: scheme.label,
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        radius: 18,
        builder: (onFocusChange) => InkWell(
          onTap: onTap,
          onFocusChange: onFocusChange,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 2.5 : 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Theme(
                    data: AppTheme.from(SchemeController.forChoice(scheme)),
                    child: MiniScreen(
                      displayWidth: width - (selected ? 5 : 2),
                      displayHeight: height - (selected ? 5 : 2),
                      child: const MiniToday(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Radio(selected: selected),
                    const SizedBox(width: 8),
                    // one line, shrunk a little before it would ever break a word
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(scheme.label, style: text.bodyMedium, maxLines: 1, softWrap: false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : Colors.transparent,
        border: Border.all(color: selected ? colors.primary : colors.onSurfaceVariant, width: 1.5),
      ),
      child: selected ? Icon(AppIconKind.check.of(context), size: 14, color: colors.onPrimary) : null,
    );
  }
}
