/// Pin diameters by state: 22 pt single, 30 pt selected or counted, 34 pt from
/// a count of ten, selected or not.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';

import 'map_repaint_test.dart' show RecordingCanvas, polygon, schemeOf;

CampusMapFeature _pin(int id, String kind) => CampusMapFeature(
  id: id,
  kind: kind,
  kindName: 'Pin',
  name: 'Pin $id',
  geometryType: 'Point',
  coordinates: const [
    [GeoCoordinate(-77.675, 43.087)],
  ],
);

/// Path.getBounds includes arc control points, so measure the drawn outline.
double _drawnWidth(Path path) {
  final metric = path.computeMetrics().single;
  var low = double.infinity;
  var high = -double.infinity;
  for (var i = 0; i < 720; i++) {
    final x = metric.getTangentForOffset(metric.length * i / 720)!.position.dx;
    low = math.min(low, x);
    high = math.max(high, x);
  }
  return high - low;
}

/// Screen diameter of the one pin on the map.
double _diameter(String kind, {required bool selected, double zoom = 3}) {
  final canvas = RecordingCanvas();
  CampusMapPainter(
    features: [polygon(1, 'Academic Building', size: 0.004), _pin(2, kind)],
    selectedId: selected ? 2 : null,
    scheme: schemeOf(Brightness.light),
    zoom: zoom,
  ).paint(canvas, const Size(400, 400));
  return _drawnWidth(canvas.paths.last) * zoom;
}

void main() {
  const tolerance = 1.5;

  group('selected pins', () {
    test('a selected count of 12 is 34 pt', () {
      expect(
        _diameter('_event:12', selected: true),
        closeTo(34, tolerance),
      );
    });

    test('the boundary is ten: 9 is 30 pt, 10 is 34 pt', () {
      expect(_diameter('_event:9', selected: true), closeTo(30, tolerance));
      expect(_diameter('_event:10', selected: true), closeTo(34, tolerance));
    });

    test('a selected single place stays 30 pt', () {
      expect(_diameter('water', selected: true), closeTo(30, tolerance));
    });

    test('and it holds at every zoom', () {
      for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
        expect(
          _diameter('_event:12', selected: true, zoom: zoom),
          closeTo(34, tolerance),
          reason: 'zoom $zoom',
        );
      }
    });
  });

  group('unselected pins', () {
    test('the boundary is ten: 9 is 30 pt, 10 is 34 pt', () {
      expect(_diameter('_event:9', selected: false), closeTo(30, tolerance));
      expect(_diameter('_event:10', selected: false), closeTo(34, tolerance));
    });

    test('a single place is 22 pt', () {
      expect(_diameter('water', selected: false), closeTo(22, tolerance));
    });

    test('selecting a count of 12 does not shrink it', () {
      expect(
        _diameter('_event:12', selected: true),
        closeTo(_diameter('_event:12', selected: false), 0.5),
      );
    });
  });
}
