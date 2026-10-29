/// Today's menu on the Dining tab lists dishes from menus already cached.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:tigerhub/data/local_backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/upstream.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LocalBackend backend;
  late JsonStore store;
  final requests = <Uri>[];

  setUp(() async {
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
    requests.clear();
    temp = Directory.systemTemp.createTempSync('tigerhub-specials');
    store = JsonStore.overrideForTesting(temp);
    final dining = jsonDecode(File('test/fixtures/tc_dining_all_empty_menus.json').readAsStringSync()) as Map<String, dynamic>;
    await store.write('tigercenter_dining', dining);
    backend = LocalBackend(
      upstream: Upstream(
        client: MockClient((request) async {
          requests.add(request.url);
          throw const SocketException('offline');
        }),
        maxRetries: 1,
      ),
      store: store,
    );
  });

  tearDown(() {
    RitClock.reset();
    backend.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Map<String, dynamic> menu(String date, List<Map<String, dynamic>> dishes) => {'location_id': 23, 'service_date': date, 'dishes': dishes};

  Map<String, dynamic> dish(String name, String date, {String? category}) => {
    'service_date': date,
    'meal_period': 'Lunch',
    'name': name,
    'category': category,
    'allergens': null,
    'dietary': null,
    'calories': null,
  };

  Future<List<Map<String, dynamic>>> specials() async {
    final body = await backend.fetch('/dining/specials');
    return (body['data'] as List).cast<Map<String, dynamic>>();
  }

  test('cached FD dishes for today are listed under their location', () async {
    await store.write('fd_menus_23', menu('2026-10-14', [dish('Tomato bisque', '2026-10-14', category: 'Soup'), dish('Grilled cheese', '2026-10-14')]));

    final items = await specials();

    expect(items.map((i) => i['name']), ['Tomato bisque', 'Grilled cheese']);
    expect(items.first['category'], 'Soup');
    expect(items.first['location_name'], 'The Cafe & Market at Crossroads');
    expect(items.map((i) => i['id']).toSet(), hasLength(2));
    expect((await backend.fetch('/dining/specials'))['availability'], 'available');
  });

  test('reading specials makes no network request for menus', () async {
    await store.write('fd_menus_23', menu('2026-10-14', [dish('Tomato bisque', '2026-10-14')]));

    await specials();

    expect(requests.where((u) => u.host.contains('fdmealplanner')), isEmpty);
  });

  test('a cached menu from another day is not listed', () async {
    await store.write('fd_menus_23', menu('2026-10-13', [dish('Tomato bisque', '2026-10-13')]));

    expect(await specials(), isEmpty);
    expect((await backend.fetch('/dining/specials'))['availability'], 'empty');
  });
}
