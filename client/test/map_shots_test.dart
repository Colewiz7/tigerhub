/// Writes the map review screenshots. Skipped unless MAP_SHOTS_DIR is set:
///
///     MAP_SHOTS_DIR=/some/dir flutter test test/map_shots_test.dart
///
/// Light, dark and grayscale at 1x, 3x, 8x and 20x on the real campus fixture,
/// plus close-ups of the pin, the event count and a selected building in each
/// of the five categories, and of the OpenStreetMap layers: water, a pitch, a
/// street name set on its path, and a named entrance.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';
import 'package:tigerhub/data/osm_features.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';

import 'golden_harness.dart';
import 'map_repaint_test.dart' show polygon, schemeOf;
import 'map_pin_test.dart' show eventPoint;

const _grayMatrix = <double>[
  0.299, 0.587, 0.114, 0, 0, //
  0.299, 0.587, 0.114, 0, 0,
  0.299, 0.587, 0.114, 0, 0,
  0, 0, 0, 1, 0,
];

Future<void> _write(
  String dir,
  String name,
  Size size,
  double ratio,
  void Function(Canvas) draw, {
  bool gray = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  if (gray) {
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..colorFilter = const ColorFilter.matrix(_grayMatrix),
    );
  }
  draw(canvas);
  if (gray) canvas.restore();
  final image = await recorder.endRecording().toImage(
    (size.width * ratio).round(),
    (size.height * ratio).round(),
  );
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  File('$dir/$name.png').writeAsBytesSync(Uint8List.sublistView(data));
}

void main() {
  final dir = Platform.environment['MAP_SHOTS_DIR'];

  testWidgets('map review screenshots', skip: dir == null, (tester) async {
    await loadGoldenFonts();
    Directory(dir!).createSync(recursive: true);
    CampusPaths.resetForTest();
    final paths = await tester.runAsync(() => CampusPaths.load());
    OsmFeatures.resetForTest();
    final osm = (await tester.runAsync(() => OsmFeatures.load()))!;
    expect(osm.isEmpty, isFalse);
    final features = [
      for (final n in ['3', '11', '35'])
        ...parseCampusMapFeatures(
          File('test/fixtures/maps_category_$n.data').readAsStringSync(),
        ).map(CampusMapFeature.fromJson),
    ];
    const view = Size(390, 520);
    final golisano = features.firstWhere((f) => f.building == 'GOL');
    final focus = CampusMapProjection(features, view).project(golisano.anchor!);

    void campus(
      Canvas canvas,
      Brightness brightness,
      double zoom, {
      int? selectedId,
    }) {
      // what the viewer does: scale about the focus, which sits mid-view
      canvas
        ..save()
        ..clipRect(Offset.zero & view);
      if (zoom > 1) {
        canvas
          ..translate(view.width / 2 - focus.dx * zoom, view.height / 2 - focus.dy * zoom)
          ..scale(zoom);
      }
      CampusMapPainter(
        features: features,
        selectedId: selectedId,
        scheme: schemeOf(brightness),
        zoom: zoom,
        paths: paths!,
        osm: osm,
      ).paint(canvas, view);
      canvas.restore();
    }

    // The same, centred on any coordinate rather than on Golisano.
    void campusAt(
      Canvas canvas,
      Brightness brightness,
      double zoom,
      GeoCoordinate at,
    ) {
      final centre = CampusMapProjection(features, view).project(at);
      canvas
        ..save()
        ..clipRect(Offset.zero & view)
        ..translate(
          view.width / 2 - centre.dx * zoom,
          view.height / 2 - centre.dy * zoom,
        )
        ..scale(zoom);
      CampusMapPainter(
        features: features,
        selectedId: null,
        scheme: schemeOf(brightness),
        zoom: zoom,
        paths: paths!,
        osm: osm,
      ).paint(canvas, view);
      canvas.restore();
    }

    GeoCoordinate middle(List<GeoCoordinate> ring) => GeoCoordinate(
      ring.fold<double>(0, (s, c) => s + c.longitude) / ring.length,
      ring.fold<double>(0, (s, c) => s + c.latitude) / ring.length,
    );
    final lake = middle(osm.water.first);
    final pitch = osm.pitch.firstWhere(
      (ring) => (middle(ring).longitude + 77.66665).abs() < 0.0005,
    );
    // the middle of a street's longest way, where its name is set
    GeoCoordinate onStreet(String name) {
      final street = osm.street.firstWhere((s) => s.name == name);
      final way = street.lines.reduce((a, b) => a.length >= b.length ? a : b);
      return way[way.length ~/ 2];
    }
    final door = osm.entrance.firstWhere(
      (e) => e.name == 'Accessible Entrance - Golisano Hall',
    );

    await tester.runAsync(() async {
      for (final brightness in Brightness.values) {
        for (final gray in [false, true]) {
          final tone = gray ? 'gray' : brightness.name;
          if (gray && brightness == Brightness.dark) continue;
          for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
            await _write(
              dir,
              '${tone}_${zoom.toInt()}x',
              view,
              2,
              (c) => campus(c, brightness, zoom),
              gray: gray,
            );
          }
          await _write(
            dir,
            '${tone}_8x_selected',
            view,
            2,
            (c) => campus(c, brightness, 8, selectedId: golisano.id),
            gray: gray,
          );
        }
      }
      // gray of the dark theme as well
      for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
        await _write(
          dir,
          'gray_dark_${zoom.toInt()}x',
          view,
          2,
          (c) => campus(c, Brightness.dark, zoom),
          gray: true,
        );
      }

      // the OpenStreetMap layers, each in light, dark and gray
      for (final tone in ['light', 'dark', 'gray']) {
        final brightness = tone == 'dark' ? Brightness.dark : Brightness.light;
        final gray = tone == 'gray';
        for (final shot in <(String, double, GeoCoordinate)>[
          ('water_3x', 3, lake),
          ('pitch_20x', 20, middle(pitch)),
          ('street_on_path_8x', 8, onStreet('Hans J. Christensen Way')),
          ('street_on_path_20x', 20, onStreet('Greenleaf Court')),
          ('entrance_name_20x', 20, door.at),
        ]) {
          await _write(
            dir,
            'closeup_osm_${shot.$1}_$tone',
            view,
            2,
            (c) => campusAt(c, brightness, shot.$2, shot.$3),
            gray: gray,
          );
        }
      }

      // seven-lobe pin, cluster and event counts, large
      const pinView = Size(400, 130);
      for (final brightness in Brightness.values) {
        final all = [
          polygon(1, 'Academic Building', size: 0.004),
          eventPoint(2, 'water', -77.6738, 43.0865),
          eventPoint(3, '_event:1', -77.6726, 43.0865),
          eventPoint(4, '_event:7', -77.6714, 43.0865),
          eventPoint(5, '_event:48', -77.6702, 43.0865),
          eventPoint(6, '_event:214', -77.6690, 43.0865),
        ];
        for (final selected in [null, 4]) {
          await _write(
            dir,
            'closeup_pins_${brightness.name}${selected == null ? '' : '_selected'}',
            pinView,
            5,
            (c) {
              c.clipRect(Offset.zero & pinView);
              final projection = CampusMapProjection(all, pinView);
              final mid = projection.project(all[3].anchor!);
              c
                ..translate(pinView.width / 2 - mid.dx * 3, pinView.height / 2 - mid.dy * 3)
                ..scale(3);
              CampusMapPainter(
                features: all,
                selectedId: selected,
                scheme: schemeOf(brightness),
                zoom: 3,
              ).paint(c, pinView);
            },
          );
        }
      }

      // a selected building in each category
      const kinds = {
        'academic': 'Academic Building',
        'residential': 'Residential Building',
        'athletic': 'Athletic Building',
        'dining': 'Restaurants',
        'other': 'Green Building',
      };
      const tile = Size(260, 190);
      for (final entry in kinds.entries) {
        for (final tone in ['light', 'dark', 'gray']) {
          final brightness = tone == 'dark' ? Brightness.dark : Brightness.light;
          final one = [
            polygon(1, entry.value, building: 'ABC', size: 0.0003),
            polygon(2, 'Academic Building', lon: -77.6735, building: 'XYZ', size: 0.0002),
          ];
          await _write(
            dir,
            'closeup_selected_${entry.key}_$tone',
            tile,
            3,
            (c) {
              c.clipRect(Offset.zero & tile);
              final projection = CampusMapProjection(one, tile);
              final mid = projection.project(one[0].anchor!);
              c
                ..translate(tile.width / 2 - mid.dx * 3, tile.height / 2 - mid.dy * 3)
                ..scale(3);
              CampusMapPainter(
                features: one,
                selectedId: 1,
                scheme: schemeOf(brightness),
                zoom: 3,
              ).paint(c, tile);
            },
            gray: tone == 'gray',
          );
        }
      }
    });
  });
}
