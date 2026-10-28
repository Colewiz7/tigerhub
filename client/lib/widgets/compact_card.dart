/// A compact Today card on a phone: a label, one short value, and an
/// optional quiet caption. The whole card opens its tab.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';

/// Marks a compact card that shares its row with another. Both then take the
/// height of a full card, caption line included, so the pair lines up.
class CompactPair extends InheritedWidget {
  const CompactPair({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CompactPair>() != null;

  @override
  bool updateShouldNotify(CompactPair oldWidget) => false;
}

class CompactCard extends StatelessWidget {
  const CompactCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.onOpen,
    this.openLabel,
    this.dragHandle,
    this.quiet = false,
  });

  final String label;

  /// Kept to about 12 characters. Null while there is nothing to say yet.
  final String? value;
  final String? caption;
  final VoidCallback? onOpen;

  /// Read after the value: "opens Campus".
  final String? openLabel;

  /// The edit controls, null outside edit mode.
  final Widget? dragHandle;

  /// Closed or past answers recede.
  final bool quiet;

  static TextStyle? valueStyle(BuildContext context) => Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17, height: 1.25, letterSpacing: 0);

  /// A card with one line each of label, value and caption.
  static double fullHeight(BuildContext context, {bool editing = false}) {
    final scaler = MediaQuery.textScalerOf(context);
    final pad = Insets.cardPaddingFor(context);
    final lines = scaler.scale(15) * 1.3 + 4 + scaler.scale(17) * 1.25 + 2 + scaler.scale(14) * 1.3;
    return pad * 2 + lines + (editing ? 32 + 6 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final editing = dragHandle != null;
    final muted = scheme.onSurfaceVariant;
    final spoken = [label, ?value, ?caption, if (!editing && onOpen != null) ?openLabel].join(', ');

    final body = Semantics(
      container: true,
      button: !editing && onOpen != null,
      label: spoken,
      excludeSemantics: true,
      onTap: editing ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(label, style: text.bodyMedium?.copyWith(fontSize: 15, height: 1.3, color: muted)),
              ),
              if (onOpen != null) ...[
                const SizedBox(width: 2),
                // keeps its room, so editing moves nothing
                Visibility.maintain(
                  key: const ValueKey('compact-card-chevron'),
                  visible: !editing,
                  child: Icon(AppIconKind.chevron.of(context), size: 15, applyTextScaling: true, color: muted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value ?? ' ',
            style: valueStyle(context)?.copyWith(color: quiet ? muted : scheme.onSurface),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: text.bodySmall?.copyWith(fontSize: 14, height: 1.3, letterSpacing: 0)),
          ],
        ],
      ),
    );

    final minHeight = CompactPair.of(context) ? fullHeight(context, editing: editing) : 0.0;
    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      borderRadius: Shapes.cardFor(context),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: InkWell(
          onTap: editing ? null : onOpen,
          canRequestFocus: !editing && onOpen != null,
          excludeFromSemantics: true,
          child: Padding(
            padding: EdgeInsets.all(Insets.cardPaddingFor(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // controls get their own row, a half cell is narrow
                if (editing) ...[
                  Align(alignment: Alignment.centerRight, child: dragHandle),
                  const SizedBox(height: 6),
                ],
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
