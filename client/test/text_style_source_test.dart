/// Canvas text cannot inherit from the theme, so a TextStyle built without a
/// fontFamily for a TextPainter paints in the platform font, not Rubik. The
/// theme walk in theme_font_test.dart cannot see that, so this scans the source.
///
/// Every `TextStyle(` in lib/ must either name a fontFamily or sit directly in
/// a `Text(` widget, which inherits the family from the theme's default text
/// style. The theme layer (lib/theme/) is exempt: its styles are merged onto
/// the base text theme, which carries Rubik. Anything else goes in
/// [_allowed], with the reason.
///
/// Weight: Rubik weighs by its wght axis, which SF on iOS may ignore. Every
/// `fontVariations: X` in lib/, theme included, must sit next to
/// `fontWeight: AppTheme.weight(X)` with the same X.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `file:line` of a TextStyle allowed to have no fontFamily, with the reason.
/// Empty: the icon glyph painter names its own family (the icon font).
const _allowed = <String, String>{};

/// Calls whose TextStyle argument inherits the family from the theme.
const _inheriting = {'Text'};

class StyleSite {
  const StyleSite(this.line, this.enclosing, this.hasFontFamily);

  final int line;
  final String enclosing;
  final bool hasFontFamily;
}

/// Source with comments and string contents blanked, same length, so offsets
/// and line numbers still match the original.
String blank(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (c == '/' && next == '*') {
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < src.length) {
        out.write('  ');
        i += 2;
      }
    } else if (c == "'" || c == '"') {
      out.write(c);
      i++;
      while (i < src.length && src[i] != c && src[i] != '\n') {
        if (src[i] == r'\' && i + 1 < src.length) {
          out.write('  ');
          i += 2;
        } else {
          out.write(' ');
          i++;
        }
      }
      if (i < src.length && src[i] == c) {
        out.write(c);
        i++;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Index just past the parenthesis that closes the one opened at [open].
int _close(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')' && --depth == 0) return i + 1;
  }
  return s.length;
}

/// Name of the call whose argument list contains [at], or '' at top level.
String _enclosingCall(String s, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    if (s[i] == ')') depth++;
    if (s[i] == '(') {
      if (depth == 0) {
        final name = RegExp(r'([\w.<>?]+)\s*$').firstMatch(s.substring(0, i));
        return name?.group(1) ?? '';
      }
      depth--;
    }
  }
  return '';
}

/// Every `TextStyle(` constructor call in [source].
List<StyleSite> styleSites(String source) {
  final code = blank(source);
  return [
    for (final m in RegExp(r'(?<![\w.])TextStyle\s*\(').allMatches(code))
      StyleSite(
        '\n'.allMatches(code.substring(0, m.start)).length + 1,
        _enclosingCall(code, m.start),
        RegExp(r'\bfontFamily\s*:').hasMatch(code.substring(m.start, _close(code, m.end - 1))),
      ),
  ];
}

/// Sites in [source] that would paint without Rubik. [file] names them.
List<String> styleProblems(String file, String source) => [
  for (final s in styleSites(source))
    if (!s.hasFontFamily &&
        !_inheriting.contains(s.enclosing) &&
        !_allowed.containsKey('$file:${s.line}'))
      '$file:${s.line}: TextStyle in ${s.enclosing.isEmpty ? 'a declaration' : s.enclosing}'
          ' has no fontFamily',
];

/// The top level arguments of the call whose parenthesis opens at [open],
/// whitespace dropped.
List<String> _arguments(String s, int open) {
  final args = <String>[];
  var depth = 0;
  var start = open + 1;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if ((c == ',' && depth == 1) || depth == 0) {
      args.add(s.substring(start, i).replaceAll(RegExp(r'\s'), ''));
      start = i + 1;
    }
    if (depth == 0) break;
  }
  return args;
}

/// Index of the parenthesis that opens the argument list holding [at].
int _openOf(String s, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = s[i];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return -1;
}

/// Each `fontVariations:` in [source] with no matching `fontWeight:` beside it.
List<String> weightProblems(String file, String source) {
  final code = blank(source);
  final problems = <String>[];
  for (final m in RegExp(r'\bfontVariations\s*:').allMatches(code)) {
    final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
    final args = _arguments(code, _openOf(code, m.start));
    String? arg(String name) => args.where((a) => a.startsWith('$name:')).map((a) => a.substring(name.length + 1)).firstOrNull;
    final variation = arg('fontVariations')!;
    final weight = arg('fontWeight');
    if (weight != 'AppTheme.weight($variation)' && weight != 'weight($variation)') {
      problems.add('$file:$line: fontVariations $variation needs fontWeight: AppTheme.weight($variation), has ${weight ?? 'none'}');
    }
  }
  return problems;
}

void main() {
  group('weight scanner', () {
    test('flags a variation with no weight', () {
      const src = '''
final s = text.bodySmall?.copyWith(color: c, fontVariations: Weights.medium);''';
      expect(weightProblems('a.dart', src), ['a.dart:1: fontVariations Weights.medium needs fontWeight: AppTheme.weight(Weights.medium), has none']);
    });

    test('flags a weight that does not match', () {
      const src = '''
final s = TextStyle(
  fontWeight: AppTheme.weight(Weights.medium),
  fontVariations: Weights.bold,
);
final t = TextStyle(fontWeight: FontWeight.w700, fontVariations: Weights.bold);''';
      expect(weightProblems('a.dart', src), hasLength(2));
    });

    test('accepts the pair, a ternary across lines, and weight() in the theme', () {
      const src = '''
final a = TextStyle(fontWeight: AppTheme.weight(Weights.medium), fontVariations: Weights.medium);
final b = base.copyWith(
  fontWeight: AppTheme.weight(today ? Weights.bold : Weights.medium),
  fontVariations: today
      ? Weights.bold
      : Weights.medium,
);
final c = TextStyle(fontSize: 9, fontWeight: weight(Weights.light), fontVariations: Weights.light);''';
      expect(weightProblems('a.dart', src), isEmpty);
    });

    test('a weight in a nested call does not count', () {
      const src = '''
final s = TextStyle(fontVariations: Weights.medium, shadows: [Shadow(color: f(fontWeight: AppTheme.weight(Weights.medium)))]);''';
      expect(weightProblems('a.dart', src), hasLength(1));
    });
  });

  test('every wght variation in lib/ also sets a matching fontWeight', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    var sites = 0;
    final problems = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      sites += RegExp(r'\bfontVariations\s*:').allMatches(blank(src)).length;
      problems.addAll(weightProblems(f.path, src));
    }
    expect(sites, greaterThan(15), reason: 'the scan found too few variations to be right');
    expect(problems, isEmpty, reason: 'SF on iOS may ignore the wght axis. Add fontWeight: AppTheme.weight(...).');
  });

  group('scanner', () {
    test('flags a canvas style with no family', () {
      const src = '''
final p = TextPainter(
  text: TextSpan(text: 'x', style: TextStyle(fontSize: 9)),
);''';
      expect(styleProblems('a.dart', src), ['a.dart:2: TextStyle in TextSpan has no fontFamily']);
    });

    test('flags a const style declaration and a nested one', () {
      const src = '''
const base = TextStyle(fontSize: 9, fontWeight: FontWeight.w600);
final p = TextPainter(text: TextSpan(style: base.copyWith(foreground: Paint()), text: 'x'));
final q = TextSpan(children: [TextSpan(style: TextStyle(height: 1))]);''';
      expect(styleProblems('a.dart', src), [
        'a.dart:1: TextStyle in a declaration has no fontFamily',
        'a.dart:3: TextStyle in TextSpan has no fontFamily',
      ]);
    });

    test('accepts a family, however it is spelled', () {
      const src = '''
final a = TextSpan(style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 9));
final b = TextSpan(style: TextStyle(color: c, fontFamily: icon.fontFamily, package: p));
const c = TextStyle(
  fontSize: 9,
  fontFamily : 'Rubik',
);''';
      expect(styleProblems('a.dart', src), isEmpty);
    });

    test('accepts a style handed to a Text widget, which inherits', () {
      const src = '''
Widget w() => Row(children: [Text(label, style: TextStyle(fontSize: 10, height: 1.1))]);''';
      expect(styleProblems('a.dart', src), isEmpty);
    });

    test('a Text elsewhere in the file does not excuse a canvas style', () {
      const src = '''
Widget w() => Text('a');
final p = TextSpan(text: 'b', style: TextStyle(fontSize: 9));''';
      expect(styleProblems('a.dart', src), hasLength(1));
    });

    test('ignores comments, strings and copyWith', () {
      const src = r'''
// TextStyle(fontSize: 9)
/* TextStyle(fontSize: 9) */
final s = 'TextStyle(fontSize: 9)';
final t = base.copyWith(fontSize: 9);
final u = const TextStyleX(fontSize: 9);''';
      expect(styleSites(src), isEmpty);
    });

    test('a fontFamily in a later, different style does not count', () {
      const src = '''
final a = TextSpan(style: TextStyle(fontSize: 9));
final b = TextSpan(style: TextStyle(fontFamily: 'Rubik'));''';
      expect(styleProblems('a.dart', src), ['a.dart:1: TextStyle in TextSpan has no fontFamily']);
    });
  });

  test('no TextStyle in lib/ paints without a family', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.startsWith('lib/theme/'))
        .toList();
    var sites = 0;
    final problems = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      sites += styleSites(src).length;
      problems.addAll(styleProblems(f.path, src));
    }
    expect(sites, greaterThan(5), reason: 'the scan found nothing, so it proves nothing');
    expect(
      problems,
      isEmpty,
      reason: 'Canvas text does not inherit the theme font. Set fontFamily: AppTheme.uiFont.',
    );
  });
}
