/// Status text with a soft rounded highlight on each clock time.
///
/// "Open until 10 PM" paints a pill behind "10 PM" only. The text stays one
/// plain [Text], so the baseline, wrapping, ellipsis and the spoken sentence
/// are exactly what they were. The pills are painted behind it from the same
/// line layout, which a TextSpan background cannot do because it has no
/// rounded corners and a WidgetSpan cannot wrap or ellipsize.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class StatusText extends StatelessWidget {
  const StatusText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextAlign? textAlign;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  static const double radius = 6;
  static const double padX = 4;
  static const double padY = 1;

  /// "10 PM", "10:30 a.m.", "noon", "midnight". A bare hour with no meridiem
  /// is not a time here.
  static final RegExp _time = RegExp(
    r'\b(?:\d{1,2}(?::\d{2})?\s?[ap]\.?m\.?(?![A-Za-z])|noon\b|midnight\b)',
    caseSensitive: false,
  );

  /// Where the times sit in [text].
  static List<TextRange> timeRanges(String text) => [
    for (final m in _time.allMatches(text)) TextRange(start: m.start, end: m.end),
  ];

  /// The pill colour: the primary at a low alpha, so it reads as a tint of
  /// whatever surface the text sits on.
  static Color tint(ColorScheme scheme) => scheme.primary.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    final ranges = timeRanges(text);
    final child = Text(text, style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign);
    if (ranges.isEmpty) return child;
    return CustomPaint(
      painter: StatusTextPainter(
        text: text,
        ranges: ranges,
        style: DefaultTextStyle.of(context).style.merge(style),
        scaler: MediaQuery.textScalerOf(context),
        direction: Directionality.of(context),
        align: textAlign ?? TextAlign.start,
        maxLines: maxLines ?? DefaultTextStyle.of(context).maxLines,
        ellipsis: (overflow ?? DefaultTextStyle.of(context).overflow) == TextOverflow.ellipsis,
        color: tint(Theme.of(context).colorScheme),
      ),
      child: child,
    );
  }
}

class StatusTextPainter extends CustomPainter {
  StatusTextPainter({
    required this.text,
    required this.ranges,
    required this.style,
    required this.scaler,
    required this.direction,
    required this.align,
    required this.maxLines,
    required this.ellipsis,
    required this.color,
  });

  final String text;
  final List<TextRange> ranges;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final TextAlign align;
  final int? maxLines;
  final bool ellipsis;
  final Color color;

  /// One rect per line a time covers, padded.
  List<Rect> highlights(Size size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textAlign: align,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: ellipsis ? '…' : null,
    )..layout(maxWidth: size.width);
    // text past the last visible line is cut, so it gets no pill
    final shown = painter.didExceedMaxLines
        ? painter.getPositionForOffset(Offset(size.width, painter.height - 1)).offset
        : text.length;
    final rects = <Rect>[];
    for (final range in ranges) {
      if (range.end > shown) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: ui.BoxHeightStyle.tight,
      );
      for (final box in boxes) {
        rects.add(Rect.fromLTRB(
          box.left - StatusText.padX,
          box.top - StatusText.padY,
          box.right + StatusText.padX,
          box.bottom + StatusText.padY,
        ));
      }
    }
    painter.dispose();
    return rects;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    for (final rect in highlights(size)) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(StatusText.radius)), fill);
    }
  }

  @override
  bool shouldRepaint(StatusTextPainter old) =>
      text != old.text ||
      style != old.style ||
      scaler != old.scaler ||
      direction != old.direction ||
      align != old.align ||
      maxLines != old.maxLines ||
      ellipsis != old.ellipsis ||
      color != old.color;
}
