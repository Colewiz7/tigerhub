import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/widgets/event_details_sheet.dart';

const _forms = [
  '&mdash;',
  '&#8212;',
  '&#x2014;',
  '&#X2014;',
  '&#8212',
  '&#x2014',
  '&#X2014',
  '&#x02014',
  '—',
];

// digits are consumed greedily, so what follows them is plain text, and a
// number that is not a character stays as written
const _edges = {
  '&#8212abc': '-abc',
  '&#x2014 and': '- and',
  '&#8212&#8212': '--',
  '&#x2014abc': '&#x2014abc',
  '&#0;': '&#0;',
  '&#xD800;': '&#xD800;',
  '&#99999999999999999999': '&#99999999999999999999',
  '&#x110000': '&#x110000',
  '&#;': '&#;',
  '&#xyz': '&#xyz',
};

void main() {
  for (final form in _forms) {
    test('event description turns $form into a plain dash', () {
      final text = eventDescriptionText('Bring a mug $form tea provided');
      expect(text, 'Bring a mug - tea provided');
      expect(text.contains('—'), isFalse);
    });

    test('recreation text turns $form into a plain dash', () {
      final text = textOf('<td>6am $form 9pm</td>');
      expect(text, '6am - 9pm');
      expect(text.contains('—'), isFalse);
    });
  }

  _edges.forEach((raw, plain) {
    test('event description reads $raw as $plain', () {
      expect(eventDescriptionText(raw), plain);
    });

    test('recreation text reads $raw as $plain', () {
      expect(textOf(raw), plain);
    });
  });
}
