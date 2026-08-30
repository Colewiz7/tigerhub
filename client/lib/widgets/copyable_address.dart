/// A mailing address whose lines can be copied one at a time.
///
/// Web order forms almost never take an address as one block. They want street,
/// city, state and ZIP in separate fields, so a single "copy" button means
/// pasting the whole thing somewhere and picking it apart by hand, every time.
/// That is the friction this removes: tap a line, paste it, move to the next
/// field.
///
/// The whole-block copy stays, because the forms that do take one blob are
/// still common enough.
///
/// Copy affordances are revealed on hover, matching the drag handles on the
/// card grid, and their space is always reserved so revealing one never shifts
/// the text. On a touch screen there is no hover, so the rows stay tappable and
/// the icon simply sits at rest opacity.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

class CopyableAddress extends StatefulWidget {
  const CopyableAddress({
    super.key,
    required this.lines,
    this.trailing,
    this.surface,
  });

  final List<String> lines;

  /// Sits beside the copy-all button, for a caution pill or similar.
  final Widget? trailing;

  /// Override the block's background when it is nested somewhere that is
  /// already at `surfaceContainerHigh`.
  final Color? surface;

  @override
  State<CopyableAddress> createState() => _CopyableAddressState();
}

class _CopyableAddressState extends State<CopyableAddress> {
  /// Which line was copied most recently, so the tick appears on that row only.
  int? _copied;

  /// Held rather than awaited, so it can be cancelled. A bare delayed future
  /// would keep running after the card is disposed, and copying two lines in
  /// quick succession would leave the first one's reset to clear the second
  /// one's tick early.
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy(String text, int index) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    _reset?.cancel();
    setState(() => _copied = index);

    // Long enough to notice, short enough not to linger over the next tap.
    _reset = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: widget.surface ?? scheme.surfaceContainerHigh,
            borderRadius: Shapes.inner,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.lines.length; i++)
                _AddressLine(
                  line: widget.lines[i],
                  copied: _copied == i,
                  onCopy: () => _copy(widget.lines[i], i),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _CopyAllButton(
              copied: _copied == -1,
              onCopy: () => _copy(widget.lines.join('\n'), -1),
            ),
            const Spacer(),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ],
    );
  }
}

class _AddressLine extends StatefulWidget {
  const _AddressLine({
    required this.line,
    required this.copied,
    required this.onCopy,
  });

  final String line;
  final bool copied;
  final VoidCallback onCopy;

  @override
  State<_AddressLine> createState() => _AddressLineState();
}

class _AddressLineState extends State<_AddressLine> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Visible on hover, on the row that was just copied, and at rest opacity
    // otherwise so a touch screen still shows the affordance exists.
    final show = _hovering || widget.copied;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: Shapes.small,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onCopy,
          // Every line is its own target, which is the whole point.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.line,
                    style: text.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
                const SizedBox(width: 10),
                // Space is reserved whether or not the icon shows, so nothing
                // shifts when a row is hovered.
                SizedBox(
                  width: 18,
                  child: Opacity(
                    opacity: show ? 1 : 0.28,
                    child: Icon(
                      widget.copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 15,
                      color: widget.copied
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyAllButton extends StatelessWidget {
  const _CopyAllButton({required this.copied, required this.onCopy});

  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: Shapes.pill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 14,
                color: copied ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(copied ? 'Copied' : 'Copy all', style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
