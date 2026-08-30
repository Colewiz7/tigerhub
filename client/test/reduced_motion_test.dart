/// Every animation must respect reduced motion.
///
/// `docs/motion-spec.md` makes this a global rule: if
/// `MediaQuery.disableAnimationsOf` or `accessibleNavigation` is set, the final
/// state paints immediately. Acceptance check 5 is that every final state stays
/// visible and usable with either enabled.
///
/// The rule is currently honoured by a check inside each animating widget,
/// seven of them. That works, and it is also exactly the shape of thing that
/// decays: the eighth animation is the one that forgets, and nothing breaks
/// visibly when it does. Someone who needs reduced motion simply gets motion.
///
/// So this fails the build instead. It is a source level check rather than a
/// behavioural one, because asserting "nothing moved" for every widget would
/// need a golden per animation and would not survive the first redesign.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Widgets and classes that animate over time. `AnimatedBuilder` is absent on
/// purpose: it rebuilds from a Listenable that may not be an animation at all.
const List<String> _animating = [
  'AnimatedSwitcher',
  'AnimatedContainer',
  'AnimatedOpacity',
  'AnimatedPositioned',
  'AnimatedAlign',
  'AnimatedPadding',
  'AnimatedDefaultTextStyle',
  'AnimatedScale',
  'AnimatedSlide',
  'AnimatedRotation',
  'TweenAnimationBuilder',
  'AnimationController',
];

/// Any of these counts as honouring the rule: an inline media query check, or
/// delegating to a shared helper if one is ever introduced.
const List<String> _honoured = [
  'disableAnimations',
  'accessibleNavigation',
  'Motion.of',
  'MotionSettings',
];

void main() {
  test('every widget that animates also handles reduced motion', () {
    final offenders = <String, List<String>>{};

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();

      final used = _animating.where(source.contains).toList();
      if (used.isEmpty) continue;
      if (_honoured.any(source.contains)) continue;

      offenders[file.path] = used;
    }

    expect(offenders, isEmpty,
        reason: 'these animate but never check whether the user asked for '
            'less motion, so reduced motion silently does nothing: '
            '${offenders.entries.map((e) => '${e.key} uses ${e.value}').join('; ')}');
  });

  test('the check is actually finding the animating widgets', () {
    // Without this, deleting every name from _animating would make the guard
    // above pass forever while testing nothing.
    final animatingFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => _animating.any(f.readAsStringSync().contains))
        .length;

    expect(animatingFiles, greaterThanOrEqualTo(5),
        reason: 'the app animates in several places, so finding almost none '
            'means the detection list has gone stale');
  });
}
