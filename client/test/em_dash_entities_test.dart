import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/widgets/event_details_sheet.dart';

const _forms = ['&mdash;', '&#8212;', '&#x2014;', '&#X2014;', '—'];

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
}
