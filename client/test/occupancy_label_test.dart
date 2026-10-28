/// Occupancy always says a word: Quiet, N% full or Busy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/theme/app_theme.dart';

void main() {
  test('14% full is Quiet', () {
    expect(occupancyLabel(const Occupancy(percentFull: 14)), 'Quiet');
  });

  test('0% full is Quiet', () {
    expect(occupancyLabel(const Occupancy(percentFull: 0)), 'Quiet');
  });

  test('15% full says its percent', () {
    expect(occupancyLabel(const Occupancy(percentFull: 15)), '15% full');
  });

  test('over capacity is Busy, whatever the percent', () {
    expect(occupancyLabel(const Occupancy(percentFull: 112, overCapacity: true)), 'Busy');
    expect(occupancyLabel(const Occupancy(percentFull: 5, overCapacity: true)), 'Busy');
  });

  test('no percent reading has no label', () {
    expect(occupancyLabel(const Occupancy(count: 12)), isNull);
  });

  testWidgets('a quiet open place shows Quiet in its row', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: const Scaffold(
        body: DiningRow(location: DiningLocation(id: 1, name: 'Gracies', isOpen: true, occupancy: Occupancy(percentFull: 14))),
      ),
    ));
    expect(find.text('Quiet'), findsOneWidget);
    expect(find.text('14% full'), findsNothing);
  });
}
