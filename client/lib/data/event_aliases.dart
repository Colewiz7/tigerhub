/// Reviewed event location aliases, pure and not wired to the map yet.
library;

enum AliasConfidence { exact, likely, reviewed, guess }

class EventAlias {
  const EventAlias({
    required this.id,
    required this.source,
    required this.confidence,
    this.names = const [],
    this.codes = const [],
    this.code,
    this.featureId,
    this.featureName,
    this.requiresCode,
    this.venue = false,
    this.reviewed = true,
  });

  final String id;

  // row of the section 2 table in event-aliases.md
  final String source;
  final AliasConfidence confidence;
  final List<String> names;
  final List<String> codes;
  final String? code;
  final int? featureId;
  final String? featureName;

  // only matches when the drupal building resolves to this code
  final String? requiresCode;

  // home athletics venue, usable after the Rochester prefix
  final bool venue;
  final bool reviewed;
}

class FieldBuildingAlias {
  const FieldBuildingAlias(
    this.name,
    this.code,
    this.source, {
    this.reviewed = true,
  });

  final String name;
  final String? code;
  final String source;
  final bool reviewed;
}

class BuildingNumberAlias {
  const BuildingNumberAlias(
    this.number,
    this.code,
    this.source, {
    this.reviewed = true,
  });

  final String number;
  final String code;
  final String source;
  final bool reviewed;
}

class AliasPin {
  const AliasPin({
    required this.rowId,
    this.code,
    this.featureId,
    this.featureName,
  });

  final String rowId;
  final String? code;
  final int? featureId;
  final String? featureName;
}

// --- code aliases: the event spelling differs from the map code ---
const codeAliases = {'SHED': 'SHD', 'SOL': 'SHH', 'GFH': 'GOR'};

// --- alias rows ---
const eventAliases = <EventAlias>[
  EventAlias(
    id: 'sau-code',
    source: '2:1',
    confidence: AliasConfidence.exact,
    codes: ['SAU'],
    names: ['STUDENT ALUMNI UNION'],
    code: 'SAU',
  ),
  EventAlias(
    id: 'sau-rooms',
    source: '2:2',
    confidence: AliasConfidence.likely,
    names: [
      '1829 ROOM',
      'MOSAIC',
      'INGLE AUDITORIUM',
      'CLARK A CONFERENCE ROOM',
    ],
    code: 'SAU',
  ),
  EventAlias(
    id: 'sau-ritz',
    source: '2:3',
    confidence: AliasConfidence.likely,
    names: ['RITZ'],
    code: 'SAU',
    requiresCode: 'SAU',
  ),
  EventAlias(
    id: 'cpc-code',
    source: '2:4',
    confidence: AliasConfidence.exact,
    codes: ['CPC'],
    code: 'CPC',
  ),
  EventAlias(
    id: 'cpc-names',
    source: '2:5',
    confidence: AliasConfidence.likely,
    names: ['CAMPUS CENTER', 'PRISM', 'BAMBOO ROOM', 'BAMBOO ROOMS'],
    code: 'CPC',
  ),
  EventAlias(
    id: 'cpc-fireside',
    source: '2:6',
    confidence: AliasConfidence.reviewed,
    names: ['FIRESIDE LOUNGE'],
    code: 'CPC',
  ),
  EventAlias(
    id: 'shd-code',
    source: '2:7',
    confidence: AliasConfidence.likely,
    codes: ['SHED'],
    names: ['STUDENT HALL FOR EXPLORATION AND DEVELOPMENT'],
    code: 'SHD',
  ),
  EventAlias(
    id: 'shd-rooms',
    source: '2:8',
    confidence: AliasConfidence.likely,
    names: [
      'MUNSON MUSIC LOFT',
      'SKLARSKY GLASS BOX THEATER',
      'GLASSBOX',
      'BOWER MAKER SHOWCASE',
    ],
    code: 'SHD',
  ),
  EventAlias(
    id: 'gol-code',
    source: '2:9',
    confidence: AliasConfidence.exact,
    codes: ['GOL'],
    code: 'GOL',
  ),
  EventAlias(
    id: 'gol-names',
    source: '2:10',
    confidence: AliasConfidence.likely,
    names: ['GOLISANO HALL', 'GCCIS ATRIUM'],
    code: 'GOL',
  ),
  EventAlias(
    id: 'cyb',
    source: '2:11',
    confidence: AliasConfidence.likely,
    codes: ['CYB'],
    names: ['CYBERSECURITY', 'CYBER SECURITY HALL'],
    code: 'CYB',
  ),
  EventAlias(
    id: 'wal',
    source: '2:12',
    confidence: AliasConfidence.exact,
    codes: ['WAL'],
    names: ['WALLACE LIBRARY'],
    code: 'WAL',
  ),
  EventAlias(
    id: 'wal-radscc',
    source: '2:13',
    confidence: AliasConfidence.likely,
    names: ['RADSCC'],
    code: 'WAL',
    requiresCode: 'WAL',
  ),
  EventAlias(
    id: 'pol',
    source: '2:14',
    confidence: AliasConfidence.exact,
    names: ['GENE POLISSENI CENTER'],
    code: 'POL',
    venue: true,
  ),
  EventAlias(
    id: 'pol-gate',
    source: '2:15',
    confidence: AliasConfidence.likely,
    names: ['GATE 3'],
    code: 'POL',
    requiresCode: 'POL',
  ),
  EventAlias(
    id: 'clk',
    source: '2:17',
    confidence: AliasConfidence.likely,
    names: ['CLARK GYMNASIUM'],
    code: 'CLK',
    venue: true,
  ),
  EventAlias(
    id: 'gor',
    source: '2:18',
    confidence: AliasConfidence.likely,
    codes: ['GOR', 'GFH'],
    names: [
      'GORDON FIELD HOUSE',
      'GORDON FIELDHOUSE',
      'FIELD HOUSE FLOOR',
      'FIELD HOUSE NORTH ENTRANCE',
    ],
    code: 'GOR',
    venue: true,
  ),
  EventAlias(
    id: 'gor-pool',
    source: '2:19',
    confidence: AliasConfidence.reviewed,
    names: ['JUDSON POOL'],
    code: 'GOR',
    venue: true,
  ),
  EventAlias(
    id: 'shd-pac',
    source: '2:21',
    confidence: AliasConfidence.reviewed,
    names: ['PERFORMING ARTS CENTER'],
    code: 'SHD',
  ),
  EventAlias(
    id: 'shd-pac-theater',
    source: '2:21',
    confidence: AliasConfidence.reviewed,
    names: ['THEATER'],
    code: 'SHD',
    requiresCode: 'SHD',
  ),
  EventAlias(
    id: 'hac',
    source: '2:22',
    confidence: AliasConfidence.likely,
    codes: ['HAC'],
    names: ['STUDENT LIFE CENTER', 'HALE-ANDREWS'],
    code: 'HAC',
  ),
  EventAlias(
    id: 'mon',
    source: '2:23',
    confidence: AliasConfidence.likely,
    names: ['MONROE HALL'],
    code: 'MON',
  ),
  EventAlias(
    id: 'smt-code',
    source: '2:24',
    confidence: AliasConfidence.exact,
    codes: ['SMT'],
    code: 'SMT',
  ),
  EventAlias(
    id: 'smt-names',
    source: '2:24',
    confidence: AliasConfidence.likely,
    names: [
      'SKALNY ROOM',
      'ALLEN CHAPEL',
      'JONES CHAPEL',
      'SCHMITT INTERFAITH',
    ],
    code: 'SMT',
  ),
  EventAlias(
    id: 'crs',
    source: '2:25',
    confidence: AliasConfidence.likely,
    names: ['CROSSROADS', 'MIDNIGHT OIL', 'RIVER ROOM'],
    code: 'CRS',
  ),
  EventAlias(
    id: 'gwh',
    source: '2:26',
    confidence: AliasConfidence.likely,
    names: ['GRACE WATSON', 'GRACIES', 'GRACIES DINING HALL'],
    code: 'GWH',
  ),
  EventAlias(
    id: 'gwh-bonfire',
    source: '2:26',
    confidence: AliasConfidence.reviewed,
    names: ['GRACE WATSON BONFIRE PIT'],
    featureName: 'Grace Watson Bonfire Pit',
  ),
  EventAlias(
    id: 'kgh',
    source: '2:27a',
    confidence: AliasConfidence.exact,
    names: ['KATE GLEASON HALL'],
    code: 'KGH',
  ),
  EventAlias(
    id: 'gle-code',
    source: '2:29',
    confidence: AliasConfidence.exact,
    codes: ['GLE'],
    code: 'GLE',
  ),
  EventAlias(
    id: 'gle-names',
    source: '2:30',
    confidence: AliasConfidence.likely,
    names: [
      'ERDLE COMMONS',
      'XEROX AUDITORIUM',
      'BRINKMAN LAB',
      'GORDON ATRIUM',
    ],
    code: 'GLE',
  ),
  EventAlias(
    id: 'lbr',
    source: '2:31',
    confidence: AliasConfidence.exact,
    codes: ['LBR'],
    names: ['LIBERAL ARTS HALL'],
    code: 'LBR',
  ),
  EventAlias(
    id: 'lbr-mckenzie',
    source: '2:32',
    confidence: AliasConfidence.likely,
    names: ['MCKENZIE COMMONS'],
    code: 'LBR',
  ),
  EventAlias(
    id: 'low-code',
    source: '2:33',
    confidence: AliasConfidence.exact,
    codes: ['LOW'],
    code: 'LOW',
  ),
  EventAlias(
    id: 'low-names',
    source: '2:33',
    confidence: AliasConfidence.likely,
    names: [
      'SUSAN R. HOLLIDAY CENTER',
      'KRUPNICKI BOARD ROOM',
      'PALMER ATRIUM',
      'GUELDENPFENNIG AUDITORIUM',
    ],
    code: 'LOW',
  ),
  EventAlias(
    id: 'boo',
    source: '2:34',
    confidence: AliasConfidence.likely,
    names: [
      'BOOTH',
      'WEBB AUDITORIUM',
      'BEVIER GALLERY',
      'INDUSTRIAL DESIGN STUDIO',
    ],
    code: 'BOO',
  ),
  EventAlias(
    id: 'uni',
    source: '2:35',
    confidence: AliasConfidence.likely,
    names: ['UNIVERSITY GALLERY'],
    code: 'UNI',
  ),
  EventAlias(
    id: 'lbj',
    source: '2:36',
    confidence: AliasConfidence.likely,
    names: ['PANARA THEATRE', 'DYER ARTS CENTER'],
    code: 'LBJ',
  ),
  EventAlias(
    id: 'mss',
    source: '2:37',
    confidence: AliasConfidence.likely,
    names: ['WEGMANS THEATER', 'WEGMANS THEATRE'],
    code: 'MSS',
  ),
  EventAlias(
    id: 'sih-name',
    source: '2:38',
    confidence: AliasConfidence.likely,
    names: ['SIMONE CENTER'],
    code: 'SIH',
  ),
  EventAlias(
    id: 'sih-code',
    source: '2:38',
    confidence: AliasConfidence.exact,
    codes: ['SIH'],
    code: 'SIH',
  ),
  EventAlias(
    id: 'dsp',
    source: '2:39',
    confidence: AliasConfidence.exact,
    codes: ['DSP'],
    names: ['DOUGLASS SPRAGUE PERRY HALL'],
    code: 'DSP',
  ),
  EventAlias(
    id: 'dsp-field',
    source: '2:40',
    confidence: AliasConfidence.reviewed,
    names: ['DSP FIELD'],
    featureName: 'DSP Field',
  ),
  EventAlias(
    id: 'shh',
    source: '2:41',
    confidence: AliasConfidence.likely,
    codes: ['SOL'],
    names: ['SOL HEUMANN'],
    code: 'SHH',
  ),
  EventAlias(
    id: 'fhb',
    source: '2:42',
    confidence: AliasConfidence.likely,
    names: ['FISH HALL B'],
    code: 'FHB-C',
  ),
  EventAlias(
    id: 'rhb',
    source: '2:43',
    confidence: AliasConfidence.likely,
    names: ['RES HALL B'],
    code: 'RHB',
  ),
  EventAlias(
    id: 'rhb-a051',
    source: '2:43',
    confidence: AliasConfidence.likely,
    names: ['A051'],
    code: 'RHB',
    requiresCode: 'RHB',
  ),
  EventAlias(
    id: 'rhc',
    source: '2:44',
    confidence: AliasConfidence.likely,
    names: ['RES HALL C'],
    code: 'RHC',
  ),
  EventAlias(
    id: 'rka',
    source: '2:45',
    confidence: AliasConfidence.likely,
    names: ['RIT FOODSHARE', 'RIVERKNOLL'],
    code: 'RKA',
  ),
  EventAlias(
    id: 'pga',
    source: '2:46',
    confidence: AliasConfidence.likely,
    names: ['PERKINS GREEN'],
    code: 'PGA',
  ),
  EventAlias(
    id: 'pga-volleyball',
    source: '2:46',
    confidence: AliasConfidence.reviewed,
    names: ['PERKINS GREEN VOLLEYBALL COURT'],
    featureName: 'Perkins Green Volleyball Court',
  ),
  EventAlias(
    id: 'gvp-name',
    source: '2:47',
    confidence: AliasConfidence.likely,
    names: ['GV 400'],
    code: 'GVP',
  ),
  EventAlias(
    id: 'gvp-code',
    source: '2:47',
    confidence: AliasConfidence.exact,
    codes: ['GVP'],
    code: 'GVP',
  ),
  EventAlias(
    id: 'gvc',
    source: '3:global-village',
    confidence: AliasConfidence.exact,
    codes: ['GVC'],
    code: 'GVC',
  ),
  EventAlias(
    id: 'gvd',
    source: '3:global-village',
    confidence: AliasConfidence.exact,
    codes: ['GVD'],
    code: 'GVD',
  ),
  EventAlias(
    id: 'gve',
    source: '3:global-village',
    confidence: AliasConfidence.exact,
    codes: ['GVE'],
    code: 'GVE',
  ),
  EventAlias(
    id: 'ppd',
    source: '2:50',
    confidence: AliasConfidence.likely,
    names: ['100 PARK POINT DRIVE'],
    code: 'PPD',
  ),
  EventAlias(
    id: 'red',
    source: '2:52',
    confidence: AliasConfidence.likely,
    names: ['RED BARN'],
    code: 'RED',
  ),
  EventAlias(
    id: 'blc',
    source: '2:53',
    confidence: AliasConfidence.likely,
    names: ['BAUSCH & LOMB CENTER'],
    code: 'BLC',
  ),
  EventAlias(
    id: 'eas',
    source: '2:54',
    confidence: AliasConfidence.exact,
    codes: ['EAS'],
    code: 'EAS',
  ),
  EventAlias(
    id: 'car',
    source: '2:55',
    confidence: AliasConfidence.exact,
    codes: ['CAR'],
    code: 'CAR',
  ),
  EventAlias(
    id: 'eng',
    source: '2:56',
    confidence: AliasConfidence.exact,
    codes: ['ENG'],
    code: 'ENG',
  ),
  EventAlias(
    id: 'ent',
    source: '2:57',
    confidence: AliasConfidence.likely,
    names: ['MCGOWAN COMMONS'],
    code: 'ENT',
  ),
  EventAlias(
    id: 'ins',
    source: '2:58',
    confidence: AliasConfidence.exact,
    codes: ['INS'],
    code: 'INS',
  ),
  EventAlias(
    id: 'hlc',
    source: '2:58',
    confidence: AliasConfidence.exact,
    codes: ['HLC'],
    code: 'HLC',
  ),
  EventAlias(
    id: 'sus',
    source: '2:58',
    confidence: AliasConfidence.exact,
    codes: ['SUS'],
    code: 'SUS',
  ),
  EventAlias(
    id: 'sla',
    source: '2:58',
    confidence: AliasConfidence.exact,
    codes: ['SLA'],
    code: 'SLA',
  ),
  EventAlias(
    id: 'csd-code',
    source: '2:59',
    confidence: AliasConfidence.exact,
    codes: ['CSD'],
    code: 'CSD',
  ),
  EventAlias(
    id: 'csd-slt',
    source: '2:59',
    confidence: AliasConfidence.likely,
    names: ['SLT COMMUNITY ROOM'],
    code: 'CSD',
  ),
];

// --- drupal field_building name to code ---
const fieldBuildingAliases = <FieldBuildingAlias>[
  FieldBuildingAlias('WALLACE LIBRARY', 'WAL', '2:60'),
  FieldBuildingAlias('CAMPUS CENTER', 'CPC', '2:60'),
  FieldBuildingAlias('GENE POLISSENI CENTER', 'POL', '2:60'),
  FieldBuildingAlias(
    'STUDENT HALL FOR EXPLORATION AND DEVELOPMENT (SHED)',
    'SHD',
    '2:60',
  ),
  FieldBuildingAlias('STUDENT DEVELOPMENT CENTER', 'CSD', '2:60'),
  FieldBuildingAlias('STUDENT ALUMNI UNION', 'SAU', '2:60'),
  FieldBuildingAlias('GOLISANO HALL', 'GOL', '2:60'),
  FieldBuildingAlias('PERFORMING ARTS CENTER', 'SHD', '2:60'),
  FieldBuildingAlias('JAMES E. BOOTH HALL', 'BOO', '2:60'),
  FieldBuildingAlias('LIBERAL ARTS HALL', 'LBR', '2:60'),
  FieldBuildingAlias('RESIDENCE HALL B', 'RHB', '2:60'),
  FieldBuildingAlias('ENGINEERING TECHNOLOGY HALL', 'ENT', '2:60'),
  FieldBuildingAlias('GORDON FIELD HOUSE AND ACTIVITIES CENTER', 'GOR', '2:60'),
  FieldBuildingAlias('THOMAS GOSNELL HALL', 'GOS', '2:60'),
  FieldBuildingAlias('MAX LOWENTHAL HALL', 'LOW', '2:60'),
  FieldBuildingAlias('LYNDON BAINES JOHNSON HALL', 'LBJ', '2:60'),
  FieldBuildingAlias('MONROE HALL', 'MON', '2:60'),
  FieldBuildingAlias('MAGIC SPELL STUDIOS', 'MSS', '2:60'),
  FieldBuildingAlias(
    'CHESTER F. CARLSON CENTER FOR IMAGING SCIENCE',
    'CAR',
    '2:60',
  ),
  FieldBuildingAlias('GEORGE EASTMAN HALL', 'EAS', '2:60'),
  FieldBuildingAlias('CROSSROADS', 'CRS', '2:60'),
  FieldBuildingAlias('LOUISE SLAUGHTER HALL', 'SLA', '2:60'),
  FieldBuildingAlias('UNIVERSITY GALLERY BUILDING', 'UNI', '2:60'),
  FieldBuildingAlias('SCHMITT INTERFAITH CENTER', 'SMT', '2:60'),
  FieldBuildingAlias('JAMES E. GLEASON HALL', 'GLE', '2:60'),
  FieldBuildingAlias('ENGINEERING HALL', 'ENG', '2:60'),
  FieldBuildingAlias('STUDENT INNOVATION HALL', 'SIH', '2:60'),
  FieldBuildingAlias('INSTITUTE HALL', 'INS', '2:60'),
  FieldBuildingAlias('UNIVERSITY SERVICES CENTER', 'USC', '2:60'),
  FieldBuildingAlias('EUGENE COLBY HALL A', 'CHA', '2:60'),
  FieldBuildingAlias('BAUSCH & LOMB CENTER', 'BLC', '2:60'),
  FieldBuildingAlias('SUSTAINABILITY INSTITUTE HALL', 'SUS', '2:60'),
  FieldBuildingAlias('RED BARN', 'RED', '2:60'),
  FieldBuildingAlias('HUGH L. CAREY HALL', 'HLC', '2:60'),
  FieldBuildingAlias('FREDERICKA DOUGLASS SPRAGUE PERRY HALL', 'DSP', '2:60'),
  FieldBuildingAlias('KATE GLEASON HALL', 'KGH', '2:60'),
  FieldBuildingAlias('VIRTUAL', null, '2:60'),
];

// --- unique building numbers, 05 is the legacy two digit form of 005 ---
const buildingNumberAliases = <BuildingNumberAlias>[
  BuildingNumberAlias('001', 'EAS', '2:54'),
  BuildingNumberAlias('004', 'SAU', '3:numbers'),
  BuildingNumberAlias('005', 'WAL', '2:13'),
  BuildingNumberAlias('076', 'CAR', '2:55'),
];

// shared with another building, so they never pin alone
const sharedBuildingNumbers = {'003', '006', '007A', '070', '087'};

// loser drops when both match in one string
const _precedence = [('CYB', 'GOL'), ('SIH', 'USC')];

const _virtualExact = {
  'TBA',
  'TBD',
  'NA',
  'N/A',
  'VARIOUS',
  'CAMPUS WIDE',
  'OFF CAMPUS VISITS',
  'OUTSIDE',
  'GROUNDS',
  'ENTIRE HOUSE',
  'ZOOM',
  'VIRTUAL',
  'ONLINE',
  'ONLINE EVENT',
  'WEBINAR',
  'ONLINE SUBMISSION',
  'SIGN UP USING LINK',
  'YOUR OWN SPACE!',
  'ROCHESTER, N.Y.',
  'ROCHESTER, NY',
};

const _virtualPrefix = [
  'ONLINE ONLY',
  'MEETING ID',
  'LINK IN CAREER CONNECT',
  'ZOOM LINKS SENT',
  'ROOM INFORMATION SENT',
  'HTTP://',
  'HTTPS://',
];

const _noneNames = [
  // off campus and same-city non-RIT venues
  'CHABAD',
  'STRONG NATIONAL MUSEUM',
  'STRONG MUSEUM',
  'MUSEUM OF PLAY',
  'ROCHESTER PUBLIC MARKET',
  'THIRD PRESBYTERIAN',
  'WASHINGTON GROVE PARK',
  'BEIKIRCH PARK',
  'GENESEE COUNTRY VILLAGE',
  'WEST HERR AUDITORIUM',
  'THE LITTLE THEATER',
  'WXXI',
  'ESL BALLPARK',
  'STOKOE FARMS',
  '200 WEST RIDGE ROAD',
  'ST. MARKS AND ST. JOHNS',
  'TAIT PRESERVE',
  'CENTRAL LIBRARY OF ROCHESTER',
  'BLUE CROSS ARENA',
  'LOUIS ALEXANDER PALESTRA',
  'FAUVER STADIUM',
  'SPEEGLE-WILBRAHAM',
  'MIDTOWN ATHLETIC CLUB',
  'GENESEE VALLEY PARK',
  // judson and tiger stadium stay off the map
  'JUDSON STADIUM',
  'TIGER STADIUM',
  // two buildings in one string
  'GRACE WATSON AND KATE GLEASON',
  'DOUGLASS SPRAGUE PERRY HALL LOBBY AND SOL HEUMANN HALL LOBBY',
];

final _prefix = RegExp(
  r'^ROCHESTER,\s*(?:N\.Y\.|NY|N\.Y)\s*(?:[,/]\s*)?',
  caseSensitive: false,
);
final _numberRoom = RegExp(r'^(\d{2,3})([A-Z]?)\s*-\s*[A-Z0-9]+$');

String _normalize(String text) => text
    .replaceAll(RegExp("['\u2019\u2018]"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class _Matcher {
  _Matcher(this.row, this.pattern);

  final EventAlias row;
  final RegExp pattern;
}

RegExp _name(String name) => RegExp(
  '(?<![A-Za-z0-9])${RegExp.escape(name).replaceAll(' ', r'\s+')}(?![A-Za-z0-9])',
  caseSensitive: false,
);

// lowercase codes only count when a room follows, so car wash isnt CAR
RegExp _codeUpper(String code) =>
    RegExp('(?<![A-Za-z0-9])$code(?![A-Za-z0-9])');
RegExp _codeLoose(String code) => RegExp(
  '(?<![A-Za-z0-9])$code(?=\\s*[-/ ]\\s*[A-Za-z]?\\d)',
  caseSensitive: false,
);

final _matchers = [
  for (final row in eventAliases) ...[
    for (final name in row.names) _Matcher(row, _name(name)),
    for (final code in row.codes) ...[
      _Matcher(row, _codeUpper(code)),
      _Matcher(row, _codeLoose(code)),
    ],
  ],
];

class _Hit {
  _Hit(this.row, this.start, this.end);

  final EventAlias row;
  final int start;
  final int end;

  String get key => row.code ?? 'f:${row.featureId ?? row.featureName}';
}

String? _buildingCode(String? building) {
  if (building == null) return null;
  final name = _normalize(building).toUpperCase();
  for (final alias in fieldBuildingAliases) {
    if (alias.name == name) return alias.code;
  }
  return null;
}

bool _isNone(String upper) {
  if (_virtualExact.contains(upper)) return true;
  for (final prefix in _virtualPrefix) {
    if (upper.startsWith(prefix)) return true;
  }
  if (upper.contains('HTTPS://') || upper.contains('HTTP://')) return true;
  for (final name in _noneNames) {
    if (_name(name).hasMatch(upper)) return true;
  }
  return false;
}

List<_Hit> _hits(String text, String? buildingCode, {bool venueOnly = false}) {
  final hits = <_Hit>[];
  for (final matcher in _matchers) {
    final row = matcher.row;
    if (venueOnly && !row.venue) continue;
    if (row.requiresCode != null && row.requiresCode != buildingCode) continue;
    for (final match in matcher.pattern.allMatches(text)) {
      hits.add(_Hit(row, match.start, match.end));
    }
  }
  return hits;
}

// a longer match swallows shorter ones inside it
List<_Hit> _outermost(List<_Hit> hits) {
  return [
    for (final hit in hits)
      if (!hits.any(
        (o) =>
            o.start <= hit.start &&
            o.end >= hit.end &&
            o.end - o.start > hit.end - hit.start,
      ))
        hit,
  ];
}

AliasPin? _resolve(List<_Hit> hits) {
  final byKey = <String, _Hit>{};
  for (final hit in _outermost(hits)) {
    byKey.putIfAbsent(hit.key, () => hit);
  }
  for (final (winner, loser) in _precedence) {
    if (byKey.containsKey(winner)) byKey.remove(loser);
  }
  if (byKey.length != 1) return null;
  final row = byKey.values.single.row;
  return AliasPin(
    rowId: row.id,
    code: row.code,
    featureId: row.featureId,
    featureName: row.featureName,
  );
}

AliasPin? _athletics(String text, String? buildingCode) {
  final prefix = _prefix.firstMatch(text);
  if (prefix == null) return null;
  final venue = text.substring(prefix.end).trim();
  if (venue.isEmpty) return null;
  final hits = _hits(
    venue,
    buildingCode,
    venueOnly: true,
  ).where((h) => h.start == 0 && h.end == venue.length).toList();
  return _resolve(hits);
}

AliasPin? _byNumber(String upper) {
  final match = _numberRoom.firstMatch(upper);
  if (match == null) return null;
  final number = '${match.group(1)!.padLeft(3, '0')}${match.group(2)}';
  if (sharedBuildingNumbers.contains(number)) return null;
  for (final alias in buildingNumberAliases) {
    if (alias.number == number) {
      return AliasPin(rowId: 'number-$number', code: alias.code);
    }
  }
  return null;
}

// null means no pin: unknown, ambiguous, virtual or off the map
AliasPin? matchEventAlias({
  String? location,
  String? building,
  bool athletics = false,
}) {
  final text = _normalize(location ?? '');
  if (text.isEmpty) return null;
  final upper = text.toUpperCase();
  final buildingCode = _buildingCode(building);

  // rochester prefix is athletics shaped even when drupal copied it
  if (athletics || _prefix.hasMatch(text)) {
    return _athletics(text, buildingCode);
  }
  if (_isNone(upper)) return null;

  final hits = _hits(text, buildingCode);
  if (hits.isNotEmpty) return _resolve(hits);

  final byNumber = _byNumber(upper);
  if (byNumber != null) return byNumber;

  // bare room, the drupal building says where
  if (buildingCode == null) return null;
  return AliasPin(rowId: 'field-building', code: buildingCode);
}
