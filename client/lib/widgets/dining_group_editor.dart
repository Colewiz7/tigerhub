/// Edit mode pieces: a group header with its actions, and the name prompt.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';

class EditGroupHeader extends StatelessWidget {
  const EditGroupHeader({
    super.key,
    required this.name,
    required this.onRename,
    this.onUp,
    this.onDown,
    this.onDelete,
  });

  final String name;
  final VoidCallback onRename;
  // null where the move is not possible
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  // only custom groups can be deleted
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      header: true,
      label: name,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Move up'): ?onUp,
        const CustomSemanticsAction(label: 'Move down'): ?onDown,
        const CustomSemanticsAction(label: 'Rename'): onRename,
        const CustomSemanticsAction(label: 'Delete group'): ?onDelete,
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.14), borderRadius: Shapes.small),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(name, style: text.titleMedium?.copyWith(color: scheme.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            _Button(icon: AppIconKind.edit, label: 'Rename', onTap: onRename),
            _Button(icon: AppIconKind.arrowUp, label: 'Move up', onTap: onUp),
            _Button(icon: AppIconKind.arrowDown, label: 'Move down', onTap: onDown),
            if (onDelete != null) _Button(icon: AppIconKind.delete, label: 'Delete group', onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.label, required this.onTap});

  final AppIconKind icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onTap,
        icon: AppIcon(icon, size: 20, color: onTap == null ? scheme.onSurface.withValues(alpha: 0.38) : scheme.primary),
      ),
    );
  }
}

// the name for a new or renamed group, null when dismissed
Future<String?> promptGroupName(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
      ],
    ),
  );
}
