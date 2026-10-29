/// Reviewed event alias table: one case per row, plus the precedence rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/event_aliases.dart';

class Case {
  const Case(
    this.id,
    this.location, {
    this.building,
    this.athletics = false,
    this.code,
    this.feature,
  });

  final String id;
  final String location;
  final String? building;
  final bool athletics;
  final String? code;
  final String? feature;
}

// example strings come from event-aliases.md section 2
const cases = [
  Case('sau-code', 'Student Alumni Union (SAU) 1829 Room', code: 'SAU'),
  Case('sau-rooms', 'Ingle Auditorium', code: 'SAU'),
  Case('sau-ritz', 'RITZ', building: 'Student Alumni Union', code: 'SAU'),
  Case('cpc-code', 'Bamboo Room (CPC-2650)', code: 'CPC'),
  Case('cpc-names', 'PRISM', code: 'CPC'),
  Case('cpc-fireside', '1550 - Fireside Lounge', code: 'CPC'),
  Case('shd-code', 'SHED-3300', code: 'SHD'),
  Case('shd-rooms', 'Munson Music Loft', code: 'SHD'),
  Case('gol-code', 'GOL-Atrium (Main Lobby)', code: 'GOL'),
  Case('gol-names', 'GCCIS Atrium', code: 'GOL'),
  Case('cyb', 'Cybersecurity Institute Rooms 1710-1730', code: 'CYB'),
  Case('wal', 'WAL - 3560', code: 'WAL'),
  Case('wal-radscc', 'RADSCC', building: 'Wallace Library', code: 'WAL'),
  Case(
    'pol',
    'Rochester, N.Y., Gene Polisseni Center',
    athletics: true,
    code: 'POL',
  ),
  Case('pol-gate', 'Gate 3', building: 'Gene Polisseni Center', code: 'POL'),
  Case(
    'clk',
    'Rochester, N.Y. / Clark Gymnasium',
    athletics: true,
    code: 'CLK',
  ),
  Case('gor', 'Field House Floor', code: 'GOR'),
  Case(
    'gor-pool',
    'Rochester, N.Y. / Judson Pool',
    athletics: true,
    code: 'GOR',
  ),
  Case('shd-pac', 'Performing Arts Center', code: 'SHD'),
  Case(
    'shd-pac-theater',
    'Theater',
    building: 'Performing Arts Center',
    code: 'SHD',
  ),
  Case('hac', 'HAC-A450', code: 'HAC'),
  Case('mon', 'Monroe Hall - 2060', code: 'MON'),
  Case('smt-code', 'SMT-A500', code: 'SMT'),
  Case('smt-names', 'Allen Chapel', code: 'SMT'),
  Case('crs', 'Midnight Oil', code: 'CRS'),
  Case('gwh', 'Gracies Dining Hall', code: 'GWH'),
  Case(
    'gwh-bonfire',
    'Grace Watson Bonfire Pit',
    feature: 'Grace Watson Bonfire Pit',
  ),
  Case('kgh', 'Kate Gleason Hall', code: 'KGH'),
  Case('gle-code', 'GLE 1910 (Erdle Commons)', code: 'GLE'),
  Case('gle-names', 'Brinkman Lab', code: 'GLE'),
  Case('lbr', 'McKenzie Commons (LBR-1251)', code: 'LBR'),
  Case('lbr-mckenzie', 'McKenzie Commons', code: 'LBR'),
  Case('low-code', 'LOW-1120', code: 'LOW'),
  Case('low-names', 'Krupnicki Board Room (3025)', code: 'LOW'),
  Case('boo', 'Booth 3471', code: 'BOO'),
  Case('uni', 'University Gallery', code: 'UNI'),
  Case('lbj', 'Panara Theatre', code: 'LBJ'),
  Case('mss', 'Wegmans Theater', code: 'MSS'),
  Case('sih-name', 'Simone Center', code: 'SIH'),
  Case(
    'sih-code',
    'SIH-1600 (University Services Center, Global Village)',
    code: 'SIH',
  ),
  Case('dsp', 'DSP 1250', code: 'DSP'),
  Case('dsp-field', 'DSP Field', feature: 'DSP Field'),
  Case('shh', 'SOL-6065', code: 'SHH'),
  Case('fhb', 'Fish Hall B', code: 'FHB-C'),
  Case('rhb', 'Res Hall B', code: 'RHB'),
  Case('rhb-a051', 'A051', building: 'Residence Hall B', code: 'RHB'),
  Case('rhc', 'Res Hall C', code: 'RHC'),
  Case('rka', 'RIT FoodShare (113 Riverknoll)', code: 'RKA'),
  Case('pga', 'Perkins Green', code: 'PGA'),
  Case(
    'pga-volleyball',
    'Perkins Green Volleyball Court',
    feature: 'Perkins Green Volleyball Court',
  ),
  Case('gvp-name', 'GV 400 First Floor Kitchen', code: 'GVP'),
  Case('gvp-code', 'GVP-1250 Wellness Studio', code: 'GVP'),
  Case('gvc', 'GVC-1000', code: 'GVC'),
  Case('gvd', 'GVD 2000', code: 'GVD'),
  Case('gve', 'GVE-3000', code: 'GVE'),
  Case('ppd', '100 Park Point Drive', code: 'PPD'),
  Case('red', 'Red Barn', code: 'RED'),
  Case('blc', 'Bausch & Lomb Center', code: 'BLC'),
  Case('eas', '001 EAS-3320', code: 'EAS'),
  Case('car', 'CAR/076 -1125', code: 'CAR'),
  Case('eng', 'ENG-1200', code: 'ENG'),
  Case('ent', 'McGowan Commons', code: 'ENT'),
  Case('ins', 'INS-1000', code: 'INS'),
  Case('hlc', 'HLC-1000', code: 'HLC'),
  Case('sus', 'SUS-1000', code: 'SUS'),
  Case('sla', 'SLA-1000', code: 'SLA'),
  Case('csd-code', 'CSD-2000', code: 'CSD'),
  Case('csd-slt', 'SLT Community Room', code: 'CSD'),
];

// section 2 rows that are guess or mixed with guess, none may ship
const guessSources = {'2:16', '2:27b', '2:28', '2:49', '2:51'};

String? pinOf(String? location, {String? building, bool athletics = false}) {
  final pin = matchEventAlias(
    location: location,
    building: building,
    athletics: athletics,
  );
  if (pin == null) return null;
  return pin.code ?? pin.featureName;
}

void main() {
  group('table', () {
    test('every row is reviewed and none is a guess', () {
      for (final row in eventAliases) {
        expect(row.reviewed, isTrue, reason: row.id);
        expect(row.confidence, isNot(AliasConfidence.guess), reason: row.id);
        expect(guessSources, isNot(contains(row.source)), reason: row.id);
        expect(
          row.code != null || row.featureName != null || row.featureId != null,
          isTrue,
          reason: row.id,
        );
      }
      for (final alias in fieldBuildingAliases) {
        expect(alias.reviewed, isTrue, reason: alias.name);
      }
      for (final alias in buildingNumberAliases) {
        expect(alias.reviewed, isTrue, reason: alias.number);
        expect(sharedBuildingNumbers, isNot(contains(alias.number)));
      }
    });

    test('row ids are unique', () {
      final ids = eventAliases.map((r) => r.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every row has a case and every case has a row', () {
      expect(
        cases.map((c) => c.id).toSet(),
        eventAliases.map((r) => r.id).toSet(),
      );
    });

    test('code aliases are the approved three', () {
      expect(codeAliases, {'SHED': 'SHD', 'SOL': 'SHH', 'GFH': 'GOR'});
    });

    test('guess rows do not pin', () {
      expect(pinOf('Duda Plaza'), isNull);
      expect(pinOf('Gleason A055'), isNull);
      expect(pinOf('Gleason 6th Floor Lounge'), isNull);
      expect(pinOf('Gleason 3 Floor'), isNull);
      expect(pinOf('RIT Inn Signature Social'), isNull);
      expect(pinOf('175 Jefferson'), isNull);
    });
  });

  group('reviewed rows', () {
    for (final c in cases) {
      test(c.id, () {
        final pin = matchEventAlias(
          location: c.location,
          building: c.building,
          athletics: c.athletics,
        );
        expect(pin, isNotNull);
        expect(pin!.rowId, c.id);
        expect(pin.code, c.code);
        expect(pin.featureName, c.feature);
      });
    }
  });

  group('code aliases', () {
    test('map to the approved codes', () {
      expect(pinOf('SHED 4300'), 'SHD');
      expect(pinOf('SOL-6065'), 'SHH');
      expect(pinOf('Commencement Weekend (GFH)'), 'GOR');
    });

    test('GV does not alias to GVP', () {
      expect(pinOf('GV'), isNull);
      expect(pinOf('GV Plaza'), isNull);
    });

    test('bare Global Village stays unmapped, named buildings pin', () {
      expect(pinOf('Global Village'), isNull);
      expect(pinOf('Global Village Plaza'), isNull);
      expect(pinOf('GV 400'), 'GVP');
      expect(pinOf('GVP-1250'), 'GVP');
    });

    test('a lowercase common word is not a code', () {
      expect(pinOf('car wash in the lot'), isNull);
      expect(pinOf('low key hangout'), isNull);
      expect(pinOf('wal 3530'), 'WAL');
    });
  });

  group('precedence', () {
    test('explicit code beats field_building', () {
      expect(pinOf('GOL-2400', building: 'Wallace Library'), 'GOL');
      expect(
        pinOf('Campus Center PRISM (CPC-1030)', building: 'Liberal Arts Hall'),
        'CPC',
      );
      expect(
        pinOf(
          'Rochester, N.Y., Gene Polisseni Center',
          building: 'George Eastman Hall',
        ),
        'POL',
      );
    });

    test('bare room falls back to field_building', () {
      expect(pinOf('1660', building: 'Wallace Library'), 'WAL');
      expect(pinOf('Atrium', building: 'Golisano Hall'), 'GOL');
      expect(
        pinOf(
          '1125 or via Zoom',
          building: 'Chester F. Carlson Center for Imaging Science',
        ),
        'CAR',
      );
      expect(pinOf('1660'), isNull);
      expect(pinOf('1660', building: 'Virtual'), isNull);
      expect(pinOf('1660', building: 'Somewhere Unlisted'), isNull);
      expect(pinOf(null, building: 'Wallace Library'), isNull);
    });

    test('CYB beats GOL', () {
      expect(pinOf('Cybersecurity Golisano Hall CYB 1710'), 'CYB');
      expect(pinOf('070 GOL-2400'), 'GOL');
    });

    test('SIH beats USC', () {
      expect(
        pinOf('SIH-1600 (University Services Center, Global Village)'),
        'SIH',
      );
    });

    test('Clark A is SAU, Gordon Atrium is GLE', () {
      expect(pinOf('2520 Clark A Conference Room'), 'SAU');
      expect(pinOf('GLE-2955 Gordon Atrium'), 'GLE');
      expect(pinOf('Gordon Atrium'), 'GLE');
    });

    test('outdoor spots pin to their own feature only', () {
      expect(pinOf('DSP Field'), 'DSP Field');
      expect(
        pinOf('Perkins Green Volleyball Court'),
        'Perkins Green Volleyball Court',
      );
      expect(pinOf('Grace Watson Bonfire Pit'), 'Grace Watson Bonfire Pit');
      expect(pinOf('Perkins Green'), 'PGA');
      expect(pinOf('DSP 1250'), 'DSP');
    });

    test('ambiguous strings give no pin', () {
      expect(pinOf('Grace Watson and Kate Gleason'), isNull);
      expect(
        pinOf('Douglass Sprague Perry Hall Lobby and Sol Heumann Hall Lobby'),
        isNull,
      );
      expect(pinOf('Student Life Center and Gordon Field House'), isNull);
      expect(pinOf('WAL 3530 and GOL 2400'), isNull);
      expect(
        pinOf('WAL 3530 and GOL 2400', building: 'Wallace Library'),
        isNull,
      );
    });
  });

  group('building numbers', () {
    test('unique numbers pin, legacy two digit included', () {
      expect(pinOf('05-2410'), 'WAL');
      expect(pinOf('005-2410'), 'WAL');
      expect(pinOf('076-1125'), 'CAR');
    });

    test('shared numbers never pin alone', () {
      for (final number in sharedBuildingNumbers) {
        expect(pinOf('$number-1400'), isNull, reason: number);
      }
      expect(pinOf('70-1400'), isNull);
    });

    test('room ranges are not building numbers', () {
      expect(pinOf('2220-2240'), isNull);
      expect(pinOf('1300/1310'), isNull);
    });

    test('a number only corroborates a code', () {
      expect(pinOf('RIT | 070 GOL-2400'), 'GOL');
      expect(pinOf('003 GOL-2400'), 'GOL');
    });
  });

  group('athletics', () {
    test('strips the Rochester prefix in each spelling', () {
      for (final prefix in [
        'Rochester, N.Y. / ',
        'Rochester, N.Y., ',
        'Rochester, NY / ',
        'rochester, n.y. / ',
      ]) {
        expect(
          pinOf('${prefix}Gene Polisseni Center', athletics: true),
          'POL',
          reason: prefix,
        );
      }
    });

    test('keeps only RIT home venues', () {
      expect(
        pinOf('Rochester, N.Y. / Gordon Field House', athletics: true),
        'GOR',
      );
      expect(pinOf('Rochester, N.Y. / Judson Pool', athletics: true), 'GOR');
      expect(
        pinOf('Rochester, N.Y. / Judson Stadium', athletics: true),
        isNull,
      );
      expect(
        pinOf('Rochester, N.Y. / Blue Cross Arena', athletics: true),
        isNull,
      );
      expect(
        pinOf('Rochester, N.Y. / Fauver Stadium', athletics: true),
        isNull,
      );
      expect(
        pinOf('Rochester, N.Y. / Doug May Field', athletics: true),
        isNull,
      );
      expect(pinOf('Rochester, N.Y.', athletics: true), isNull);
    });

    test('away games never pin', () {
      expect(pinOf('Potsdam, N.Y. / Clarkson Arena', athletics: true), isNull);
      expect(pinOf('Gene Polisseni Center', athletics: true), isNull);
    });

    test(
      'a copied drupal athletics string never falls back to the building',
      () {
        expect(
          pinOf('Rochester, N.Y., Doug May Field', building: 'Wallace Library'),
          isNull,
        );
      },
    );
  });

  group('none list', () {
    test('virtual and placeholders', () {
      for (final text in [
        'Zoom',
        'zoom',
        'Virtual',
        'Online',
        'Online Event',
        'Online Only - Teams',
        'Webinar',
        'Meeting ID: 95357917999',
        'https://rit.zoom.us/j/1',
        'Link in Career Connect',
        'Zoom links sent after registration',
        'Room information sent after registration',
        'Online Submission',
        'Sign Up Using Link',
        'Your own space!',
        'TBA',
        'TBD',
        'NA',
        'Various',
        'Campus wide',
        'Off Campus Visits',
        'Outside',
        'Grounds',
        'Entire House',
      ]) {
        expect(pinOf(text, building: 'Wallace Library'), isNull, reason: text);
      }
    });

    test('hybrid rooms still resolve', () {
      expect(pinOf('4600 or via Zoom', building: 'Golisano Hall'), 'GOL');
    });

    test('off campus', () {
      expect(
        pinOf(
          'Chabad house - 3018 East River Road - Campus access from the Lobozzo Alumni House parking lot',
        ),
        isNull,
      );
      expect(pinOf('Chabad House', building: 'Student Alumni Union'), isNull);
      expect(
        pinOf('Kate Gleason Auditorium, Central Library of Rochester'),
        isNull,
      );
      expect(pinOf('Strong National Museum of Play'), isNull);
      expect(pinOf("St. Mark's and St. John's"), isNull);
      expect(pinOf('Rochester Public Market'), isNull);
    });

    test('Judson and Tiger Stadium stay unmapped', () {
      expect(pinOf('Judson Stadium'), isNull);
      expect(pinOf('Tiger Stadium'), isNull);
    });
  });

  group('field_building', () {
    test('names resolve to codes', () {
      expect(
        pinOf(
          'Room 2480',
          building: 'Student Hall for Exploration and Development (SHED)',
        ),
        'SHD',
      );
      expect(pinOf('Room 2480', building: 'Performing Arts Center'), 'SHD');
      expect(pinOf('Room 2480', building: 'Eugene Colby Hall A'), 'CHA');
      expect(pinOf('Room 2480', building: 'university services center'), 'USC');
    });
  });
}
