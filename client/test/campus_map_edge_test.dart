import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_style.dart';

const west = CampusMapFeature(
  id: 1,
  kind: 'water',
  kindName: 'Water fountains',
  name: 'West fountain',
  geometryType: 'Point',
  coordinates: [
    [GeoCoordinate(-77.68, 43.08)],
  ],
);

const east = CampusMapFeature(
  id: 2,
  kind: 'aed',
  kindName: 'Defibrillators',
  name: 'East AED',
  geometryType: 'Point',
  coordinates: [
    [GeoCoordinate(-77.67, 43.09)],
  ],
);

const panMargin = 80.0;

ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness);

Widget app(Brightness brightness) => MaterialApp(
  theme: AppTheme.from(scheme(brightness)),
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 600,
      child: CampusMapView(
        result: const Result(value: Collection(data: [west, east], stale: false), state: DataState.ok),
        events: const Result(value: Collection(data: [], stale: false), state: DataState.ok),
      ),
    ),
  ),
);

// the fixed palette ground, not the wallpaper theme
Color ground(ColorScheme scheme) => MapPalette.of(scheme.brightness).ground;

Finder get painterFinder => find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is CampusMapPainter);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('painter fills ground past the canvas by the pan margin, ${brightness.name}', (tester) async {
      await tester.pumpWidget(app(brightness));
      final size = tester.getSize(painterFinder);
      final expected = (Offset.zero & size).inflate(panMargin);
      expect(tester.renderObject(painterFinder), paints..rect(rect: expected, color: ground(scheme(brightness))));
    });
  }

  for (final zooms in [0, 3, 6]) {
    testWidgets('panning to every extreme at ${zooms == 0 ? 1 : zooms} zoom steps keeps ground under the viewport', (tester) async {
      await tester.pumpWidget(app(Brightness.light));
      for (var i = 0; i < zooms; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
      }
      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final controller = viewer.transformationController!;
      final viewport = Offset.zero & tester.getSize(find.byType(InteractiveViewer));
      final canvas = Offset.zero & tester.getSize(painterFinder);
      final expected = canvas.inflate(panMargin);

      for (final drag in const [Offset(-4000, 0), Offset(4000, 0), Offset(0, -4000), Offset(0, 4000), Offset(-4000, -4000), Offset(4000, 4000), Offset(4000, -4000), Offset(-4000, 4000)]) {
        await tester.drag(find.byType(InteractiveViewer), drag);
        await tester.pumpAndSettle();
        final visible = MatrixUtils.transformRect(controller.value, expected);
        expect(visible.left, lessThanOrEqualTo(viewport.left + 0.01), reason: 'left edge exposed after $drag');
        expect(visible.top, lessThanOrEqualTo(viewport.top + 0.01), reason: 'top edge exposed after $drag');
        expect(visible.right, greaterThanOrEqualTo(viewport.right - 0.01), reason: 'right edge exposed after $drag');
        expect(visible.bottom, greaterThanOrEqualTo(viewport.bottom - 0.01), reason: 'bottom edge exposed after $drag');
        expect(tester.renderObject(painterFinder), paints..rect(rect: expected));
      }
    });
  }
}
