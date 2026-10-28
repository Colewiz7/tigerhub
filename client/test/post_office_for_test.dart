/// Each housing area knows its post office, which package pickup reads.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';

void main() {
  test('the area envelope keeps its post office', () {
    final area = HousingArea.fromJson({'id': 'global-village', 'name': 'Global Village', 'post_office': 'global-village'});
    expect(area.postOffice, 'global-village');
    expect(HousingArea.fromJson({'id': 'rit-inn', 'name': 'RIT Inn', 'direct_delivery': true}).postOffice, isNull);
  });

  final areas = [
    for (final (id, office) in [('residence-halls', 'dsp'), ('global-village', 'global-village'), ('greek-houses', 'global-village')])
      HousingArea(id: id, name: id, postOffice: office),
    const HousingArea(id: 'rit-inn', name: 'RIT Inn', directDelivery: true),
  ];

  test('an area maps to its office', () {
    expect(postOfficeFor(areas, 'global-village'), 'global-village');
    expect(postOfficeFor(areas, 'residence-halls'), 'dsp');
    expect(postOfficeFor(areas, 'greek-houses'), 'global-village');
  });

  test('direct delivery, no home and an unknown area have no office', () {
    expect(postOfficeFor(areas, 'rit-inn'), isNull);
    expect(postOfficeFor(areas, null), isNull);
    expect(postOfficeFor(areas, 'mars'), isNull);
  });
}
