/// Finds row text that ran out of lines, the ellipsis a reader sees.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/section_nav.dart';
import 'package:tigerhub/widgets/status_row.dart';

/// Subtitles of nav rows and status rows on screen that ran out of lines.
List<String> truncatedRowText(WidgetTester tester) => [
  for (final element in _subtitles(tester))
    if ((element.renderObject! as RenderParagraph).didExceedMaxLines) (element.widget as RichText).text.toPlainText(),
];

/// Subtitles of nav rows and status rows on screen allowed more than one line.
List<String> multiLineRowText(WidgetTester tester) => [
  for (final element in _subtitles(tester))
    if ((element.widget as RichText).maxLines != 1) (element.widget as RichText).text.toPlainText(),
];

/// Subtitles of nav rows and status rows on screen held to one line.
List<String> singleLineRowText(WidgetTester tester) => [
  for (final element in _subtitles(tester))
    if ((element.widget as RichText).maxLines == 1) (element.widget as RichText).text.toPlainText(),
];

Iterable<Element> _subtitles(WidgetTester tester) {
  final subtitles = {
    for (final row in tester.widgetList<SectionNavRow>(find.byType(SectionNavRow))) row.spec.subtitle,
    for (final row in tester.widgetList<StatusRow>(find.byType(StatusRow))) ?row.subtitle,
  };
  return [
    for (final row in [find.byType(SectionNavRow), find.byType(StatusRow)])
      for (final element in find.descendant(of: row, matching: find.byType(RichText)).evaluate())
        if (subtitles.contains((element.widget as RichText).text.toPlainText())) element,
  ];
}
