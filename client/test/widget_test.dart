/// Client tests. No network: the API client is driven with a mock http client.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/freshness.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/widgets/bounded_list.dart';
import 'package:tigerhub/widgets/more_row.dart';
import 'package:tigerhub/widgets/occupancy_chip.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('data states', () {
    test('first launch with no cache and no server is priming', () async {
      final api = ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final results = await api.dining().toList();
      expect(results.first.state, DataState.priming);
      expect(results.last.state, DataState.priming);
      expect(results.last.hasData, isFalse);
    });

    test('successful fetch is ok and caches for next launch', () async {
      final body = jsonEncode({
        'data': [
          {'id': 23, 'name': 'Crossroads', 'is_open': true, 'occupancy': null},
        ],
        'stale': false,
        'last_updated': '2026-08-28T12:00:00Z',
      });
      final api = ApiClient(client: MockClient((_) async => http.Response(body, 200)));
      final results = await api.dining().toList();
      expect(results.last.state, DataState.ok);
      expect(results.last.value!.data.single.name, 'Crossroads');

      // A second client with no network must still serve the cached payload.
      final offline = ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final replay = await offline.dining().toList();
      expect(replay.first.state, DataState.stale);
      expect(replay.first.value!.data.single.name, 'Crossroads');
      expect(replay.last.state, DataState.failing);
      expect(replay.last.hasData, isTrue, reason: 'stale cache must never become an error');
    });

    test('server reported staleness is mirrored, not recomputed', () async {
      final body = jsonEncode({'data': [], 'stale': true, 'last_updated': null});
      final api = ApiClient(client: MockClient((_) async => http.Response(body, 200)));
      final results = await api.dining().toList();
      expect(results.last.state, DataState.stale);
    });
  });

  group('occupancy chip', () {
    testWidgets('renders nothing when there is no sensor', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OccupancyChip(occupancy: null))),
      );
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('no data'), findsNothing);
    });

    testWidgets('renders a percentage when a sensor exists', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(
              occupancy: Occupancy(count: 75, maxOcc: 150, percentFull: 50),
            ),
          ),
        ),
      );
      expect(find.text('50% full'), findsOneWidget);
    });
  });

  group('occupancy honesty', () {
    testWidgets('over capacity says busy, not a precise percentage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(
              occupancy: Occupancy(
                count: 46, maxOcc: 38, percentFull: 100, overCapacity: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('busy'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing,
          reason: 'a wrong denominator must not be quoted as a precise figure');
    });

    testWidgets('a count with no denominator shows the count, not a ratio',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(occupancy: Occupancy(count: 235, percentFull: null)),
          ),
        ),
      );
      expect(find.text('235 here now'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('bounded cards', () {
    // The grid cell height the home screen uses.
    const cellHeight = 340.0;
    const rowHeight = 62.0;
    const footerHeight = 34.0;

    Widget boxed(Widget child, {double height = cellHeight}) => MaterialApp(
          home: Scaffold(body: Center(child: SizedBox(height: height, child: child))),
        );

    testWidgets('shows only rows that fit and counts the rest', (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 12,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
      ));
      // (340 - 34) / 62 = 4 rows fit alongside the footer.
      expect(find.text('row 3'), findsOneWidget);
      expect(find.text('row 4'), findsNothing);
      expect(find.text('+8 locations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the footer is fully inside the box, never clipped',
        (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 12,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
      ));
      final box = tester.getRect(find.byType(BoundedList));
      final footer = tester.getRect(find.byType(MoreRow));
      expect(footer.bottom, lessThanOrEqualTo(box.bottom + 0.5),
          reason: 'the "+N more" row must be visible, not cut off');
    });

    testWidgets('no footer when everything fits', (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 3,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
      ));
      expect(find.byType(MoreRow), findsNothing);
      expect(find.text('row 2'), findsOneWidget);
    });

    testWidgets('a shorter box withholds more, and still says so',
        (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 12,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
        height: 2 * rowHeight + footerHeight,
      ));
      expect(find.text('row 1'), findsOneWidget);
      expect(find.text('row 2'), findsNothing);
      expect(find.text('+10 locations'), findsOneWidget);
    });

    testWidgets('dining bounds itself and keeps open locations first',
        (tester) async {
      final locations = [
        for (var i = 0; i < 12; i++)
          DiningLocation(
            id: i,
            name: 'Place ${i.toString().padLeft(2, '0')}',
            isOpen: i < 3,
          ),
      ];
      await tester.pumpWidget(boxed(
        DiningCard(
          result: Result(
            value: Collection(data: locations, stale: false),
            state: DataState.ok,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Place 00'), findsOneWidget);
      expect(find.text('Place 11'), findsNothing);
      expect(find.byType(MoreRow), findsOneWidget);
    });

    testWidgets('more row is tappable for the future detail view',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoreRow(hidden: 7, noun: 'locations', onTap: () => tapped++),
          ),
        ),
      );
      await tester.tap(find.text('+7 locations'));
      expect(tapped, 1);
    });
  });

  group('freshness line', () {
    testWidgets('fresh data gets no annotation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FreshnessLine(state: DataState.ok, fetchedAt: DateTime.now()),
          ),
        ),
      );
      expect(find.textContaining('updated'), findsNothing);
    });

    testWidgets('stale data shows a quiet timestamp and no spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FreshnessLine(
              state: DataState.stale,
              fetchedAt: DateTime.now().subtract(const Duration(minutes: 40)),
            ),
          ),
        ),
      );
      expect(find.text('updated 40m ago'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('failing shows the same text with a warning icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FreshnessLine(
              state: DataState.failing,
              fetchedAt: DateTime.now().subtract(const Duration(hours: 2)),
            ),
          ),
        ),
      );
      expect(find.text('updated 2h ago'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });
  });

  test('age formatting', () {
    final now = DateTime.now();
    expect(formatAge(now), 'just now');
    expect(formatAge(now.subtract(const Duration(minutes: 40))), '40m ago');
    expect(formatAge(now.subtract(const Duration(hours: 3))), '3h ago');
    expect(formatAge(now.subtract(const Duration(days: 2))), '2d ago');
  });
}
