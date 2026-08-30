/// SHED makerspace real time equipment availability.
///
/// Ported from `backend/app/scrapers/makerspace.py`.
///
/// Endpoint: POST https://make.rit.edu/graphql, no auth. Verified 2026-08-28,
/// 56 machines across 10 rooms.
///
/// Equipment availability only. Their `makerspaces { hours }` query is
/// deliberately not used: it returns `closed: true` on every row with an ISO
/// timestamp where a weekday belongs, which is a bug in their data. SHED hours
/// are hardcoded in `assets/config/shed_hours.json` instead (CLAUDE.md 8,
/// decision 3).
///
/// Introspection is disabled in production, so this query was built from their
/// open source schema at rit-construct-makerspace/access-control-server.
library;

import '../upstream.dart';

const String makerspaceSource = 'makerspace_equipment';
const String makerspaceGraphqlUrl = 'https://make.rit.edu/graphql';

/// `equipments` excludes archived items. `allEquipment` includes them, so it is
/// the wrong query for an availability view.
const String makerspaceQuery = '''
{
  equipments {
    id
    name
    subName
    inUse
    numAvailable
    numInUse
    archived
    room { id name }
  }
}
''';

List<Map<String, dynamic>> parseMakerspace(Map<String, dynamic> payload) {
  final errors = payload['errors'];
  if (errors != null) throw UpstreamError('GraphQL errors: $errors');

  final items = (payload['data'] as Map<String, dynamic>?)?['equipments'];
  if (items is! List) {
    throw UpstreamError('GraphQL response had no data.equipments');
  }

  final out = <Map<String, dynamic>>[];
  for (final item in items) {
    if (item is! Map<String, dynamic>) continue;
    if (item['archived'] == true) continue;
    final room = item['room'] as Map<String, dynamic>? ?? const {};
    final subName = (item['subName'] as String? ?? '').trim();

    out.add({
      'id': '${item['id']}',
      'name': item['name'] ?? '',
      'sub_name': subName.isEmpty ? null : subName,
      'room': room['name'],
      'in_use': item['inUse'] == true,
      'num_available': item['numAvailable'] ?? 0,
      'num_in_use': item['numInUse'] ?? 0,
    });
  }
  return out;
}

Future<Map<String, dynamic>> scrapeMakerspace(Upstream http) async {
  final payload = await http.postJson(
    makerspaceGraphqlUrl,
    {'query': makerspaceQuery},
  ) as Map<String, dynamic>;

  final parsed = parseMakerspace(payload);
  if (parsed.isEmpty) {
    throw UpstreamError('makerspace returned zero equipment rows');
  }
  return {'equipment': parsed};
}

// --- projections -------------------------------------------------------

List<Map<String, dynamic>> equipmentIn(
  Map<String, dynamic>? snapshot,
  String? room,
) {
  final all = <Map<String, dynamic>>[
    for (final e in snapshot?['equipment'] as List<dynamic>? ?? const [])
      if (room == null || (e as Map<String, dynamic>)['room'] == room)
        e as Map<String, dynamic>,
  ];

  all.sort((a, b) {
    final byRoom = '${a['room']}'.compareTo('${b['room']}');
    return byRoom != 0 ? byRoom : '${a['name']}'.compareTo('${b['name']}');
  });
  return all;
}

/// Per room totals, so a room can be summarised without listing every machine.
List<Map<String, dynamic>> roomSummary(Map<String, dynamic>? snapshot) {
  final rooms = <String, Map<String, dynamic>>{};

  for (final raw in snapshot?['equipment'] as List<dynamic>? ?? const []) {
    final item = raw as Map<String, dynamic>;
    final room = '${item['room']}';
    final row = rooms.putIfAbsent(
      room,
      () => {'room': item['room'], 'machines': 0, 'available': 0, 'in_use': 0},
    );
    row['machines'] = (row['machines'] as int) + 1;
    row['available'] =
        (row['available'] as int) + (item['num_available'] as int? ?? 0);
    row['in_use'] = (row['in_use'] as int) + (item['num_in_use'] as int? ?? 0);
  }

  final out = rooms.values.toList()
    ..sort((a, b) => '${a['room']}'.compareTo('${b['room']}'));
  return out;
}
