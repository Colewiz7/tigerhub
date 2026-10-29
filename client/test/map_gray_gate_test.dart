/// Grayscale acceptance gate.
///
/// The five category tints sit within a few percent of each other in
/// luminance, so a grayscale screenshot cannot tell them apart by fill. The
/// category glyph is the gray cue, and it shows from 3x.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_style.dart';

import 'golden_harness.dart';
import 'map_repaint_test.dart' show polygon, schemeOf;

// rec 601 luma, 0 to 255
double gray(Color c) => 255 * (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);

const kinds = {
  MapCategory.academic: 'Academic Building',
  MapCategory.residential: 'Residential Building',
  MapCategory.athletic: 'Athletic Building',
  MapCategory.dining: 'Restaurants',
  MapCategory.other: 'Green Building',
};

void main() {
  for (final entry in {'light': MapPalette.light, 'dark': MapPalette.dark}.entries) {
    test('fills alone do not separate the categories in gray, ${entry.key}', () {
      final p = entry.value;
      final lumas = [for (final c in MapCategory.values) gray(p.fill(c))];
      var closest = 255.0;
      for (var i = 0; i < lumas.length; i++) {
        for (var j = i + 1; j < lumas.length; j++) {
          closest = closest < (lumas[i] - lumas[j]).abs()
              ? closest
              : (lumas[i] - lumas[j]).abs();
        }
      }
      // under 3 of 255 levels is below what anyone reads as two grays
      expect(closest, lessThan(3), reason: 'if this ever passes, re-check the gate');
    });
  }

  testWidgets('in gray the glyph tells the categories apart from 3x', (tester) async {
    await loadGoldenFonts();
    const size = Size(300, 300);
    const ratio = 2.0;
    final zooms = [2.9, 3.0, 8.0];
    final renders = (await tester.runAsync(() async {
      final out = <List<Uint8List>>[];
      for (final zoom in zooms) {
        final shots = <Uint8List>[];
        for (final kind in kinds.values) {
          final recorder = ui.PictureRecorder();
          // what the viewer does: scale about the centre of the view
          final canvas = Canvas(recorder)
            ..scale(ratio)
            ..translate(size.width / 2, size.height / 2)
            ..scale(zoom)
            ..translate(-size.width / 2, -size.height / 2);
          CampusMapPainter(
            features: [polygon(1, kind, building: 'ABC', size: 0.004)],
            selectedId: null,
            scheme: schemeOf(Brightness.light),
            zoom: zoom,
          ).paint(canvas, size);
          final image = await recorder.endRecording().toImage(
            (size.width * ratio).round(),
            (size.height * ratio).round(),
          );
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          final luma = Uint8List(data.lengthInBytes ~/ 4);
          for (var i = 0; i < luma.length; i++) {
            luma[i] = gray(
              Color.fromARGB(
                255,
                data.getUint8(i * 4),
                data.getUint8(i * 4 + 1),
                data.getUint8(i * 4 + 2),
              ),
            ).round();
          }
          shots.add(luma);
        }
        out.add(shots);
      }
      return out;
    }))!;

    int differing(Uint8List a, Uint8List b) {
      var n = 0;
      for (var i = 0; i < a.length; i++) {
        if ((a[i] - b[i]).abs() > 24) n++;
      }
      return n;
    }

    for (var z = 0; z < zooms.length; z++) {
      for (var i = 0; i < kinds.length; i++) {
        for (var j = i + 1; j < kinds.length; j++) {
          final n = differing(renders[z][i], renders[z][j]);
          if (zooms[z] < 3) {
            expect(n, 0, reason: 'no glyph below 3x, ${zooms[z]}x pair $i/$j');
          } else {
            expect(
              n,
              greaterThan(15),
              reason: 'glyphs must differ in gray at ${zooms[z]}x, pair $i/$j',
            );
          }
        }
      }
    }
  });
}
