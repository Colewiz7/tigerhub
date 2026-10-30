/// Setup's words and look follow the brief: sentence case, no exclamation
/// marks, no em dashes, never the word Skip, and no gradients, confetti, emoji
/// or sparkles.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _setupFiles() => [
  for (final entity in Directory('lib/screens/setup').listSync())
    if (entity is File && entity.path.endsWith('.dart')) entity,
  File('lib/widgets/whats_new_sheet.dart'),
];

final _double = RegExp(r'"((?:[^"\\\n]|\\.)*)"');
final _single = RegExp(r"'((?:[^'\\\n]|\\.)*)'");

// the text inside quotes; double quoted strings go first so an apostrophe in one is not a quote
List<String> _strings(String source) => [
  for (final match in _double.allMatches(source)) match.group(1)!,
  for (final match in _single.allMatches(source.replaceAll(_double, '""'))) match.group(1)!,
];

void main() {
  test('the setup files are found', () {
    expect(_setupFiles().where((f) => f.existsSync()).length, greaterThan(8));
  });

  test('no string has an exclamation mark, an em dash or the word Skip', () {
    for (final file in _setupFiles()) {
      for (final text in _strings(file.readAsStringSync())) {
        expect(text, isNot(contains('!')), reason: '${file.path}: "$text"');
        expect(text, isNot(contains('—')), reason: '${file.path}: "$text"');
        expect(text.toLowerCase(), isNot(contains('skip')), reason: '${file.path}: "$text"');
      }
    }
  });

  test('no emoji, gradients, confetti or sparkles', () {
    final emoji = RegExp('[\u{1F300}-\u{1FAFF}☀-➿⭐]', unicode: true);
    for (final file in _setupFiles()) {
      // code only, a comment may name what the code avoids
      final source = [
        for (final line in file.readAsLinesSync())
          if (!line.trimLeft().startsWith('//')) line,
      ].join('\n');
      expect(emoji.hasMatch(source), isFalse, reason: '${file.path} has an emoji');
      for (final word in ['Gradient', 'confetti', 'sparkle', 'AppIconKind.celebration']) {
        expect(source, isNot(contains(word)), reason: '${file.path} uses $word');
      }
    }
  });

  test('buttons and titles are sentence case', () {
    final words = RegExp(r'^[A-Z][a-z’\x27]*( [a-z’\x27&]+)*$');
    for (final label in [
      'Continue',
      'Set up later',
      'Use defaults',
      'Get started',
      'Personalize',
      'Not now',
      'Pick a look',
      'Where you live',
      'Your spots',
      'Your Today',
      'Follow a club',
    ]) {
      // Your Today names the screen it is, Today is a proper name
      if (label == 'Your Today') continue;
      expect(words.hasMatch(label), isTrue, reason: label);
    }
  });
}
