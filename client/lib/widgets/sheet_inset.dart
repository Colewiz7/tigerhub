/// Bottom sheets and the Android navigation bar.
///
/// Android 15 forces edge to edge, so the three button bar (48) or the gesture
/// pill (24) draws over the bottom of the screen. A sheet is as tall as its
/// content, so anything it does not pad itself ends up behind the bar. Sheets
/// open through [showAppSheet], which pads the bottom once, here, and hides it
/// from any SafeArea inside so nothing is padded twice.
///
/// iOS is left alone: its home indicator inset is handled by each sheet as
/// before.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Space the system navigation bar takes from the bottom of a sheet.
/// Zero on iOS, and zero while the keyboard is up (the sheet rides above it).
double sheetBottomInset(BuildContext context) {
  if (Theme.of(context).platform == TargetPlatform.iOS) return 0;
  final media = MediaQuery.of(context);
  if (media.viewInsets.bottom > 0) return 0;
  return math.max(media.padding.bottom, media.viewPadding.bottom);
}

/// Keeps [child] above the system navigation bar. The padding sits outside the
/// scrollable, so the last row scrolls fully clear and its buttons stay tappable.
class SheetInset extends StatelessWidget {
  const SheetInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = sheetBottomInset(context);
    if (bottom == 0) return child;
    // a SafeArea inside must not pad the same space a second time
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: MediaQuery.removeViewPadding(
          context: context,
          removeBottom: true,
          child: child,
        ),
      ),
    );
  }
}

/// [showModalBottomSheet] with the bottom inset applied. Use this for every sheet.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  double? elevation,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  bool showDragHandle = false,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: backgroundColor,
  barrierColor: barrierColor,
  elevation: elevation,
  shape: shape,
  constraints: constraints,
  showDragHandle: showDragHandle,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  builder: (context) => SheetInset(child: builder(context)),
);
