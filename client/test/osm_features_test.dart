/// The bundled OpenStreetMap layers.
///
/// Like the walking paths, this asset is generated and committed rather than
/// fetched, so nothing else would notice if it were truncated, re-extracted
/// with the wrong bounds, or stripped of its licence.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/osm_features.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.text);

  final String? text;

  @override
  Future<ByteData> load(String key) async {
    final text = this.text;
    if (text == null) throw FlutterError('missing $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  final raw = jsonDecode(
    File('assets/map/osm_features.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  setUp(OsmFeatures.resetForTest);

  test('the asset still carries its ODbL credit', () {
    expect(raw['attribution'], contains('OpenStreetMap'));
    expect(raw['attribution'], contains('ODbL'));
    expect(raw['source'], contains('openstreetmap.org/copyright'));
  });

  test('the real asset parses into every layer', () {
    final features = OsmFeatures.parse(raw);
    expect(features.isEmpty, isFalse);
    expect(features.water, isNotEmpty);
    expect(features.waterway, isNotEmpty);
    expect(features.park, isNotEmpty);
    expect(features.pitch, isNotEmpty);
    expect(features.building, isNotEmpty);
    expect(features.entrance, isNotEmpty);
    expect(features.street, isNotEmpty);
  });

  test('rings have three points and lines have two', () {
    final features = OsmFeatures.parse(raw);
    for (final ring in [
      ...features.water,
      ...features.park,
      ...features.pitch,
      ...features.building,
    ]) {
      expect(ring.length, greaterThanOrEqualTo(3));
    }
    for (final line in [
      ...features.waterway,
      for (final s in features.street) ...s.lines,
    ]) {
      expect(line.length, greaterThanOrEqualTo(2));
    }
  });

  test('nothing strayed outside the campus box', () {
    final box = raw['bbox'] as Map<String, dynamic>;
    final west = (box['west'] as num).toDouble();
    final east = (box['east'] as num).toDouble();
    final south = (box['south'] as num).toDouble();
    final north = (box['north'] as num).toDouble();
    final features = OsmFeatures.parse(raw);
    for (final p in [
      for (final ring in features.building) ...ring,
      for (final e in features.entrance) e.at,
    ]) {
      expect(p.longitude, inInclusiveRange(west, east));
      expect(p.latitude, inInclusiveRange(south, north));
    }
  });

  test('Judson and Tiger Stadium never reach a name', () {
    final features = OsmFeatures.parse(raw);
    final names = [
      for (final s in features.street) s.name,
      for (final e in features.entrance) ?e.name,
    ].join('|').toLowerCase();
    expect(names, isNot(contains('judson')));
    expect(names, isNot(contains('tiger stadium')));
  });

  test('unknown keys are ignored', () {
    final features = OsmFeatures.parse({
      'future': [1, 2, 3],
      'park': [
        [
          [-77.67, 43.08],
          [-77.66, 43.08],
          [-77.66, 43.09],
        ],
      ],
    });
    expect(features.park, hasLength(1));
    expect(features.water, isEmpty);
  });

  test('a half-read layer costs the extras, never the map', () {
    final features = OsmFeatures.parse({
      'park': [
        [
          [-77.67, 43.08],
          [-77.66, 43.08],
          [-77.66, 43.09],
        ],
      ],
      'building': 'corrupt',
    });
    expect(features.isEmpty, isTrue);
  });

  test('a corrupt asset leaves the map intact', () async {
    expect((await OsmFeatures.load(_Bundle('{not json'))).isEmpty, isTrue);
  });

  test('a missing asset leaves the map intact', () async {
    expect((await OsmFeatures.load(_Bundle(null))).isEmpty, isTrue);
  });

  test('the real asset loads from a bundle once', () async {
    final text = File('assets/map/osm_features.json').readAsStringSync();
    final first = await OsmFeatures.load(_Bundle(text));
    final second = await OsmFeatures.load(_Bundle(null));
    expect(first.isEmpty, isFalse);
    expect(identical(first, second), isTrue);
  });
}
