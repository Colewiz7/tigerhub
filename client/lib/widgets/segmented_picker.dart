/// A segmented control in the iOS shape: one track, one sliding thumb.
library;

import 'package:flutter/material.dart';

import '../motion/reduce_motion.dart';
import '../theme/tokens.dart';

class SegmentedPicker<T extends Object> extends StatelessWidget {
  const SegmentedPicker({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final keys = labels.keys.toList();
    final at = keys.indexOf(value);
    final duration = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    // three short labels stop growing at 1.15 so they stay one size and one line
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);
    final scale = scaler.scale(1).clamp(1.0, 1.15);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Container(
        height: height * scale,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                keys.length < 2 ? 0 : -1 + 2 * at / (keys.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / keys.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: Shapes.small,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final key in keys)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: key == value,
                      label: labels[key],
                      excludeSemantics: true,
                      onTap: () => onChanged(key),
                      child: InkWell(
                        borderRadius: Shapes.small,
                        onTap: () => onChanged(key),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                labels[key]!,
                                maxLines: 1,
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: key == value
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
