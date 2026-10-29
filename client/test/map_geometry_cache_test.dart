/// The painted geometry (outlines, label ink, pin buckets) is built once per
/// set of inputs, not once per paint.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';

import 'map_repaint_test.dart' show RecordingCanvas, polygon, schemeOf;

final _features = [
  polygon(1, 'Academic Building', lon: -77.678, building: 'AAA'),
  polygon(2, 'Residential Building', lon: -77.676, building: 'BBB'),
  polygon(3, 'Athletic Building', lon: -77.674, building: 'CCC'),
];

const _size = Size(400, 400);

const _paths = CampusPaths(
  foot: [
    [GeoCoordinate(-77.676, 43.084), GeoCoordinate(-77.670, 43.088)],
  ],
  road: [],
);

RecordingCanvas _paint(
  List<CampusMapFeature> features, {
  double zoom = 1,
  int? selectedId,
  Size size = _size,
  ColorScheme? scheme,
  CampusPaths paths = _paths,
}) {
  final canvas = RecordingCanvas();
  CampusMapPainter(
    features: features,
    selectedId: selectedId,
    scheme: scheme ?? schemeOf(Brightness.light),
    zoom: zoom,
    paths: paths,
  ).paint(canvas, size);
  return canvas;
}

int _builds(void Function() body) {
  final before = CampusMapPainter.geometryBuilds;
  body();
  return CampusMapPainter.geometryBuilds - before;
}

void main() {
  setUp(() {
    CampusMapPainter.resetGeometryCacheForTest();
    CampusMapProjection.resetCacheForTest();
  });

  test('repeated paints of one list build the geometry once', () {
    expect(
      _builds(() {
        for (final zoom in const [1.0, 1.0, 2.0, 3.0, 8.0, 20.0, 1.0]) {
          _paint(_features, zoom: zoom);
        }
      }),
      1,
    );
  });

  test('a selection change reuses it', () {
    expect(
      _builds(() {
        _paint(_features);
        _paint(_features, selectedId: 2);
        _paint(_features, selectedId: 3, zoom: 8);
      }),
      1,
    );
  });

  test('an equal list that is a new object reuses it', () {
    // The map screen builds a fresh list on every State.build from the same
    // feature objects, so equal inputs arrive as a new instance.
    expect(
      _builds(() {
        _paint(_features);
        _paint([..._features]);
        _paint([..._features], zoom: 3);
      }),
      1,
    );
  });

  test('a reused geometry paints exactly what a cold build paints', () {
    final cold = _paint(_features, zoom: 3, selectedId: 2);
    CampusMapPainter.resetGeometryCacheForTest();
    CampusMapProjection.resetCacheForTest();
    _paint(_features);
    final warm = _paint([..._features], zoom: 3, selectedId: 2);
    expect(warm.draws.length, cold.draws.length);
    for (var i = 0; i < cold.draws.length; i++) {
      expect(warm.draws[i].kind, cold.draws[i].kind, reason: 'draw $i');
      expect(warm.draws[i].paint.color, cold.draws[i].paint.color);
      expect(
        warm.draws[i].path?.getBounds(),
        cold.draws[i].path?.getBounds(),
        reason: 'draw $i',
      );
    }
  });

  group('changed inputs still rebuild', () {
    test('a different feature', () {
      expect(
        _builds(() {
          _paint(_features);
          _paint([..._features.take(2), polygon(9, 'Dining', lon: -77.67)]);
        }),
        2,
      );
    });

    test('a feature dropped', () {
      expect(
        _builds(() {
          _paint(_features);
          _paint(_features.take(2).toList());
        }),
        2,
      );
    });

    test('a different size', () {
      expect(
        _builds(() {
          _paint(_features);
          _paint(_features, size: const Size(300, 500));
        }),
        2,
      );
    });

    test('a different colour scheme', () {
      expect(
        _builds(() {
          _paint(_features);
          _paint(_features, scheme: schemeOf(Brightness.dark));
        }),
        2,
      );
    });

    test('different paths', () {
      expect(
        _builds(() {
          _paint(_features);
          _paint(_features, paths: const CampusPaths.empty());
        }),
        2,
      );
    });
  });
}
