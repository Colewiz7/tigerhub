/// every search box in the app
///
/// cancel shows while focused, like ios
/// tapping outside drops focus on every platform
library;

import 'package:flutter/material.dart';

import 'app_icon.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  void _clear() {
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: focusNode,
    builder: (context, _) => Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onTapOutside: (_) => focusNode.unfocus(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: Icon(AppIconKind.search.of(context)),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clear,
                      icon: Icon(AppIconKind.close.of(context)),
                    ),
            ),
          ),
        ),
        if (focusNode.hasFocus)
          // same tap group, so pressing it isnt a tap outside
          TextFieldTapRegion(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton(
                onPressed: () {
                  _clear();
                  focusNode.unfocus();
                },
                child: const Text('Cancel'),
              ),
            ),
          ),
      ],
    ),
  );
}
