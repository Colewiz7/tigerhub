/// Offline campus map painted directly from cached GeoJSON.
///
/// No tiles, API key, or map dependency. The horizontal place list is the
/// keyboard and screen-reader equivalent of tapping pins on the canvas.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/campus_paths.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import 'campus_event_mapper.dart';
import 'empty_state.dart';
import 'freshness.dart';

class CampusMapView extends StatefulWidget {
  const CampusMapView({super.key, required this.result, this.events});

  final Result<Collection<CampusMapFeature>> result;
  final Result<Collection<CampusEvent>>? events;

  @override
  State<CampusMapView> createState() => _CampusMapViewState();
}

class _CampusMapViewState extends State<CampusMapView> {
  final _transform = TransformationController();
  final _mapFocus = FocusNode(debugLabel: 'Campus map');
  String? _kind;
  int? _selectedId;
  bool _showEvents = false;

  /// Empty until the bundled asset decodes. The map paints without it, then
  /// again with it, rather than holding the whole screen back for 114 KB.
  CampusPaths _paths = const CampusPaths.empty();

  @override
  void initState() {
    super.initState();
    CampusPaths.load().then((paths) {
      if (mounted) setState(() => _paths = paths);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    _mapFocus.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 5.0);
    final applied = target / current;
    if (applied == 1) return;
    _transform.value = _transform.value.clone()
      ..scaleByDouble(applied, applied, 1, 1);
  }

  KeyEventResult _handleMapKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.add ||
        event.logicalKey == LogicalKeyboardKey.equal ||
        event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.5);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.minus ||
        event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / 1.5);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading campus map');
    }

    final all = widget.result.value?.data ?? const <CampusMapFeature>[];
    if (all.isEmpty) {
      return const EmptyState(
        kind: EmptyKind.sourceDown,
        title: 'Campus map is unavailable',
      );
    }

    final kinds = <String, String>{
      for (final feature in all)
        if (!feature.kind.startsWith('_')) feature.kind: feature.kindName,
    };
    final backdrop = [
      for (final feature in all)
        if (feature.kind == '_campus') feature,
    ];
    final visible = [
      for (final feature in all)
        if (!feature.kind.startsWith('_') &&
            (_kind == null || feature.kind == _kind))
          feature,
    ];
    final eventMap = mapCampusEvents(
      widget.events?.value?.data ?? const <CampusEvent>[],
      all,
    );
    final eventFeatures = [
      for (final group in eventMap.groups) group.mapFeature,
    ];
    final mapFeatures = [
      ...backdrop,
      ...(_showEvents ? eventFeatures : visible),
    ];
    final selected = visible.where((f) => f.id == _selectedId).firstOrNull;
    final selectedEvent = eventMap.groups
        .where((group) => group.id == _selectedId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final mode = SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.place_rounded),
                  label: Text('Places'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.event_rounded),
                  label: Text('Events'),
                ),
              ],
              selected: {_showEvents},
              onSelectionChanged: (selection) => setState(() {
                _showEvents = selection.single;
                _selectedId = null;
                _transform.value = Matrix4.identity();
              }),
            );
            final toolbar = _MapToolbar(
              kinds: _showEvents ? const {} : kinds,
              selectedKind: _kind,
              onKindChanged: (kind) => setState(() {
                _kind = kind;
                _selectedId = null;
                _transform.value = Matrix4.identity();
              }),
              onFit: () => _transform.value = Matrix4.identity(),
            );

            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mode,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: toolbar),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 320, child: mode),
                const Spacer(),
                toolbar,
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: Shapes.card,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: Focus(
                        focusNode: _mapFocus,
                        onKeyEvent: _handleMapKey,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: 1,
                          maxScale: 5,
                          boundaryMargin: const EdgeInsets.all(80),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () => _zoomBy(1.5),
                            onTapUp: (details) {
                              _mapFocus.requestFocus();
                              final projection = CampusMapProjection(
                                mapFeatures,
                                Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                ),
                                boundsFeatures: all,
                              );
                              final hit = projection.nearest(
                                details.localPosition,
                              );
                              if (hit != null) {
                                setState(() => _selectedId = hit.id);
                              }
                            },
                            // Repaints as the viewer scales, which is what
                            // lets labels and the scale bar hold a constant
                            // on-screen size instead of growing with the map.
                            child: ValueListenableBuilder<Matrix4>(
                              valueListenable: _transform,
                              builder: (context, matrix, _) => CustomPaint(
                                size: Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                ),
                                painter: CampusMapPainter(
                                  features: mapFeatures,
                                  boundsFeatures: all,
                                  selectedId: _selectedId,
                                  scheme: Theme.of(context).colorScheme,
                                  zoom: matrix.getMaxScaleOnAxis(),
                                  paths: _paths,
                                  onSelect: (feature) =>
                                      setState(() => _selectedId = feature.id),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Fixed, and outside the InteractiveViewer, so it does not
                    // zoom the way the scale bar deliberately does.
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _MapLegend(scheme: Theme.of(context).colorScheme),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: selected == null && selectedEvent == null ? 92 : 146,
          child: _showEvents
              ? selectedEvent == null
                    ? _EventStrip(
                        result: eventMap,
                        onSelect: (group) =>
                            setState(() => _selectedId = group.id),
                      )
                    : _SelectedEventGroup(
                        group: selectedEvent,
                        onClose: () => setState(() => _selectedId = null),
                      )
              : selected == null
              ? _PlaceStrip(
                  features: visible,
                  selectedId: _selectedId,
                  onSelect: (feature) =>
                      setState(() => _selectedId = feature.id),
                )
              : _SelectedPlace(
                  feature: selected,
                  onClose: () => setState(() => _selectedId = null),
                ),
        ),
      ],
    );
  }
}

class _EventStrip extends StatelessWidget {
  const _EventStrip({required this.result, required this.onSelect});

  final CampusEventMapResult result;
  final ValueChanged<MappedEventGroup> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${result.mapped} mapped · ${result.unmapped} without a location',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 6),
      Expanded(
        child: result.groups.isEmpty
            ? Center(
                child: Text(
                  'No events could be placed today',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: result.groups.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final group = result.groups[index];
                  return SizedBox(
                    width: 230,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: Shapes.inner,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelect(group),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                group.events.length == 1
                                    ? group.events.single.title
                                    : '${group.events.length} events',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                group.building,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class _SelectedEventGroup extends StatelessWidget {
  const _SelectedEventGroup({required this.group, required this.onClose});

  final MappedEventGroup group;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: Shapes.inner,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: group.events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final event = group.events[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${group.building} · ${formatClock(event.startsAt)}'
                      '${event.organizer == null ? '' : ' · ${event.organizer}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Close event details',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    ),
  );
}

class _MapToolbar extends StatelessWidget {
  const _MapToolbar({
    required this.kinds,
    required this.selectedKind,
    required this.onKindChanged,
    required this.onFit,
  });

  final Map<String, String> kinds;
  final String? selectedKind;
  final ValueChanged<String?> onKindChanged;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedLabel = selectedKind == null
        ? 'All places'
        : kinds[selectedKind] ?? 'All places';
    final selectedIcon = selectedKind == null
        ? Icons.apps_rounded
        : mapPlaceIcon(selectedKind!);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kinds.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Filter map places',
            onSelected: (value) => onKindChanged(value.isEmpty ? null : value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: '',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.apps_rounded),
                  title: Text('All places'),
                ),
              ),
              for (final entry in kinds.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(mapPlaceIcon(entry.key)),
                    title: Text(entry.value),
                  ),
                ),
            ],
            child: Material(
              color: scheme.surfaceContainerHigh,
              shape: Shapes.pill,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(selectedIcon, size: 19),
                    const SizedBox(width: 8),
                    Text(selectedLabel),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Fit campus',
          onPressed: onFit,
          icon: const Icon(Icons.center_focus_strong_rounded),
        ),
      ],
    );
  }
}

class _PlaceStrip extends StatelessWidget {
  const _PlaceStrip({
    required this.features,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CampusMapFeature> features;
  final int? selectedId;
  final ValueChanged<CampusMapFeature> onSelect;

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: features.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (context, index) {
      final feature = features[index];
      return SizedBox(
        width: 210,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(feature),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _PlaceCategoryMark(feature: feature),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          feature.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          feature.where.isEmpty
                              ? feature.kindName
                              : feature.where,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SelectedPlace extends StatelessWidget {
  const _SelectedPlace({required this.feature, required this.onClose});

  final CampusMapFeature feature;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: Shapes.inner,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          _PlaceCategoryMark(feature: feature, size: 46, iconSize: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  feature.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (feature.where.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    feature.where,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (feature.note case final note?) ...[
                  const SizedBox(height: 3),
                  Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close details',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    ),
  );
}

class _PlaceCategoryMark extends StatelessWidget {
  const _PlaceCategoryMark({
    required this.feature,
    this.size = 38,
    this.iconSize = 20,
  });

  final CampusMapFeature feature;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: feature.kindName,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            mapPlaceIcon(feature.kind),
            size: iconSize,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class CampusMapProjection {
  /// Reuses the last projection when nothing that shapes it has changed.
  ///
  /// Building one walks every anchor, sorts them twice for the medians, then
  /// reduces over roughly 9550 coordinates for the bounds. That measured
  /// **7.27ms of a 13.9ms paint**, recomputed identically every frame, which
  /// only started to matter when the map began repainting on every zoom frame.
  /// The inputs are stable across those frames, so the work is pure waste.
  factory CampusMapProjection(
    List<CampusMapFeature> features,
    Size size, {
    List<CampusMapFeature>? boundsFeatures,
  }) {
    final cached = _cache;
    if (cached != null &&
        cached.size == size &&
        identical(cached.features, features) &&
        identical(cached._boundsFeatures, boundsFeatures)) {
      return cached;
    }
    return _cache = CampusMapProjection._(features, size, boundsFeatures);
  }

  CampusMapProjection._(this.features, this.size, this._boundsFeatures) {
    final boundsFeatures = _boundsFeatures;
    final candidates = boundsFeatures ?? features;
    final anchors = [for (final feature in candidates) ?feature.anchor];
    final medianLongitude = _median(anchors.map((p) => p.longitude).toList());
    final medianLatitude = _median(anchors.map((p) => p.latitude).toList());
    final core = candidates.where((feature) {
      final anchor = feature.anchor;
      if (anchor == null) return false;
      // RIT publishes a few locations several miles from the main campus,
      // including the Inn and downtown partner buildings. They stay in the
      // result list, but must not shrink the initial campus view to dots.
      return (anchor.longitude - medianLongitude).abs() <= 0.018 &&
          (anchor.latitude - medianLatitude).abs() <= 0.012;
    });
    final points = core.expand((f) => f.coordinates.expand((ring) => ring));
    if (points.isNotEmpty) {
      minLongitude = points.map((p) => p.longitude).reduce(math.min);
      maxLongitude = points.map((p) => p.longitude).reduce(math.max);
      minLatitude = points.map((p) => p.latitude).reduce(math.min);
      maxLatitude = points.map((p) => p.latitude).reduce(math.max);
    }
    _matchViewportAspect();
  }

  /// Grows the visible bounds to the shape of the window.
  ///
  /// A wide window shows more ground. It never shows the same ground stretched
  /// wider, which is what this used to do: it forced a 2.35:1 minimum aspect,
  /// and since the campus in view is 2342m by 2085m (1.12:1) that stretched
  /// longitude by 2.09x and left latitude alone, so every building came out
  /// over twice as wide as it really is.
  ///
  /// Simply fitting the campus instead is honest but wasteful: a 1.12:1 map in
  /// the 1.86:1 panel of a 970px window uses 60% of it and strands 357px of
  /// dead width. Growing the bounds fills the panel and keeps the scale on
  /// both axes identical, which is also what lets the scale bar mean anything.
  void _matchViewportAspect() {
    final availableWidth = math.max(size.width - padding * 2, 1);
    final availableHeight = math.max(size.height - padding * 2, 1);
    final target = availableWidth / availableHeight;

    final cosine = math.cos(((minLatitude + maxLatitude) / 2) * math.pi / 180);
    final latitudeSpan = math.max(maxLatitude - minLatitude, 0.000001);
    final geographicWidth = math.max(
      (maxLongitude - minLongitude) * cosine,
      0.000001,
    );

    if (geographicWidth / latitudeSpan < target) {
      final grow = (latitudeSpan * target - geographicWidth) / cosine / 2;
      minLongitude -= grow;
      maxLongitude += grow;
    } else {
      final grow = (geographicWidth / target - latitudeSpan) / 2;
      minLatitude -= grow;
      maxLatitude += grow;
    }
  }

  final List<CampusMapFeature> features;
  final Size size;
  final List<CampusMapFeature>? _boundsFeatures;

  static CampusMapProjection? _cache;

  /// Only for tests that need a cold build.
  static void resetCacheForTest() => _cache = null;
  double minLongitude = -77.69;
  double maxLongitude = -77.66;
  double minLatitude = 43.075;
  double maxLatitude = 43.095;

  static const double padding = 34;

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    values.sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  /// The whole padded panel.
  ///
  /// The bounds were grown to this shape in the constructor, so filling it is
  /// isotropic by construction rather than by a second scaling rule here.
  late final Rect mapRect = _computeMapRect();

  Rect _computeMapRect() {
    final width = math.max(size.width - padding * 2, 1).toDouble();
    final height = math.max(size.height - padding * 2, 1).toDouble();
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  Offset project(GeoCoordinate point) {
    final longitudeSpan = math.max(maxLongitude - minLongitude, 0.000001);
    final latitudeSpan = math.max(maxLatitude - minLatitude, 0.000001);
    final rect = mapRect;
    return Offset(
      rect.left + (point.longitude - minLongitude) / longitudeSpan * rect.width,
      rect.top + (maxLatitude - point.latitude) / latitudeSpan * rect.height,
    );
  }

  CampusMapFeature? nearest(Offset position) {
    CampusMapFeature? nearestFeature;
    var nearestDistance = 28.0;
    for (final feature in features.where((f) => f.geometryType == 'Point')) {
      final anchor = feature.anchor;
      if (anchor == null) continue;
      final distance = (project(anchor) - position).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestFeature = feature;
      }
    }
    return nearestFeature;
  }
}

/// The round distance a scale bar should span, given what would fit.
///
/// Kept as a separate function so the choice can be tested without a canvas.
int scaleBarMetres(double target) {
  const steps = [10, 20, 25, 50, 100, 200, 250, 500, 1000];
  return steps.firstWhere((step) => step >= target, orElse: () => steps.last);
}

/// How a campus outline is drawn.
///
/// maps.rit.edu names the sub-category each outline came from, so a parking
/// apron and a lecture hall arrive already distinguishable. Before this they
/// were painted identically, and since lots are large, they read as enormous
/// buildings and buried the campus they surround.
enum MapFamily {
  /// Quads, gardens, solar fields. Ground, not structure.
  open(0),

  /// Lots and aprons. Context you cross, not somewhere you go.
  parking(1),

  /// Anything you can walk into. Drawn last, so it sits on top.
  built(2);

  const MapFamily(this.rank);

  /// Painting order, ground upward.
  final int rank;
}

/// Familiar category symbols used by pins and the filter menu.
///
/// These are intentionally Material symbols rather than another illustration
/// set: emergency, restroom, transit, and payment icons should be recognized
/// immediately on a dense map.
IconData mapPlaceIcon(String kind) => switch (kind) {
  'water' => Icons.water_drop_rounded,
  'ev_charge' => Icons.ev_station_rounded,
  'blue_light' => Icons.emergency_share_rounded,
  'aed' => Icons.health_and_safety_rounded,
  'restroom_all_gender' => Icons.wc_rounded,
  'restroom_accessible' => Icons.accessible_rounded,
  'atm' => Icons.local_atm_rounded,
  'changing_table' => Icons.baby_changing_station_rounded,
  'entrance_accessible' => Icons.accessible_forward_rounded,
  'bus_stop' => Icons.directions_bus_rounded,
  'bike_rack' => Icons.pedal_bike_rounded,
  'reload' => Icons.add_card_rounded,
  _ when kind.startsWith('_event:') => Icons.event_rounded,
  _ => Icons.place_rounded,
};

/// How each family is painted, in one place, so the map and the legend that
/// explains it cannot disagree.
///
/// Measured against the map field (surface plus primary at 0.035), because
/// colour here is validated rather than eyeballed:
///
///                                light  dark
///   building fill                 1.17  1.42   under the 1.5 shape floor
///   building edge (outline)       4.08  5.50   so the edge carries it
///   parking edge (outline @0.55)  2.00  2.56   present, clearly secondary
///   open space (tertiary @0.32)   1.54  2.08   reads as ground
///
/// No step of the surface ramp works as an open-space fill: the best of them
/// measured 1.11 light and 1.21 dark, both under the floor. Vegetation uses
/// `tertiary` instead (hue 53, an olive), which is a scheme role rather than
/// an invented hue.
({Paint? fill, Paint? edge}) mapFamilyPaints(
  MapFamily family,
  ColorScheme scheme,
) {
  switch (family) {
    case MapFamily.open:
      return (
        fill: Paint()..color = scheme.tertiary.withValues(alpha: 0.32),
        edge: null,
      );
    case MapFamily.parking:
      return (
        fill: null,
        edge: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = scheme.outline.withValues(alpha: 0.55),
      );
    case MapFamily.built:
      return (
        fill: Paint()..color = scheme.surfaceContainerHighest,
        edge: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = scheme.outline,
      );
  }
}

/// Classifies an outline by the sub-category name maps.rit.edu gave it.
MapFamily mapFamily(CampusMapFeature feature) {
  final name = feature.kindName.toLowerCase();
  if (name.contains('parking')) return MapFamily.parking;
  if (name.contains('quad') ||
      name.contains('garden') ||
      name.contains('solar')) {
    return MapFamily.open;
  }
  return MapFamily.built;
}

class CampusMapPainter extends CustomPainter {
  CampusMapPainter({
    required this.features,
    this.boundsFeatures,
    required this.selectedId,
    required this.scheme,
    this.onSelect,
    this.zoom = 1,
    this.paths = const CampusPaths.empty(),
  });

  final List<CampusMapFeature> features;
  final List<CampusMapFeature>? boundsFeatures;
  final int? selectedId;
  final ColorScheme scheme;
  final ValueChanged<CampusMapFeature>? onSelect;

  /// The InteractiveViewer's current scale.
  ///
  /// The canvas is painted in unzoomed coordinates and the viewer scales the
  /// result, so without this everything grows together and zooming in reveals
  /// nothing new. Text and rules divide by it to hold a constant on-screen
  /// size, which also means more building labels fit as you zoom in.
  final double zoom;

  /// The bundled OpenStreetMap walking network. Empty until the asset loads,
  /// and empty forever if it fails, which costs the paths and nothing else.
  final CampusPaths paths;

  @override
  SemanticsBuilderCallback get semanticsBuilder => _buildSemantics;

  List<CustomPainterSemantics> _buildSemantics(Size size) {
    final projection = CampusMapProjection(
      features,
      size,
      boundsFeatures: boundsFeatures,
    );
    return [
      for (final feature in features)
        if (feature.geometryType == 'Point' && feature.anchor != null)
          CustomPainterSemantics(
            key: ValueKey(feature.id),
            rect: Rect.fromCircle(
              center: projection.project(feature.anchor!),
              radius: 22,
            ),
            properties: SemanticsProperties(
              label: [
                feature.kindName,
                feature.name,
                ?feature.building,
              ].join(', '),
              textDirection: TextDirection.ltr,
              button: true,
              onTap: onSelect == null ? null : () => onSelect!(feature),
            ),
          ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final projection = CampusMapProjection(
      features,
      size,
      boundsFeatures: boundsFeatures,
    );
    final mapRect = projection.mapRect;
    canvas.drawRRect(
      RRect.fromRectAndRadius(mapRect.inflate(18), const Radius.circular(32)),
      Paint()..color = scheme.primary.withValues(alpha: 0.035),
    );

    // A quiet tiger-stripe field gives the map the same identity as the
    // masthead without competing with pins or pretending to be map data.
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(mapRect.inflate(18), const Radius.circular(32)),
    );
    final stripePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = scheme.primary.withValues(alpha: 0.035);
    for (var y = mapRect.top + 70; y < mapRect.bottom; y += 105) {
      final stripe = Path()
        ..moveTo(mapRect.left - 30, y)
        ..cubicTo(
          mapRect.left + mapRect.width * .28,
          y - 34,
          mapRect.left + mapRect.width * .62,
          y + 38,
          mapRect.right + 30,
          y - 10,
        );
      canvas.drawPath(stripe, stripePaint);
    }
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(mapRect.inflate(18), const Radius.circular(32)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = scheme.primary.withValues(alpha: 0.12),
    );

    // Measured, not picked by eye. Against the map background the surface
    // steps are all too close to carry a shape on their own, and the light
    // scheme is the worse of the two:
    //
    //                        light   dark
    //   surfaceContainerHigh  1.22   1.35
    //   surfaceContainerHighest 1.29  1.58
    //   outlineVariant edge on fill  1.32 both
    //
    // So the edge carries the building rather than the fill, and it uses
    // `outline` (3.48 light, 3.88 dark) rather than `outlineVariant`. The fill
    // stays quiet. This is why buildings read as faint wireframes before: both
    // the fill and the edge were within a third of their background.
    // Drawn from the ground up, so the things you actually walk into sit on
    // top. The paints are shared with the legend so the two cannot drift.
    final familyPaints = {
      for (final family in MapFamily.values)
        family: mapFamilyPaints(family, scheme),
    };

    // Collected while the polygons are drawn, so a label knows the shape it
    // belongs to and can be skipped when it will not fit inside it.
    final labelCandidates = <({String text, Rect bounds, double area})>[];

    final areas = features.where((f) => f.geometryType != 'Point').toList()
      ..sort((a, b) => mapFamily(a).rank.compareTo(mapFamily(b).rank));

    // Paths belong on the ground: over the grass and the lots they cross, and
    // under the buildings they run between. The list is sorted by family, so
    // the moment the first building comes up is the moment to draw them.
    var pathsDrawn = false;

    for (final feature in areas) {
      final family = mapFamily(feature);
      if (!pathsDrawn && family == MapFamily.built) {
        _paintPaths(canvas, projection, mapRect, scheme);
        pathsDrawn = true;
      }
      for (final ring in feature.coordinates) {
        if (ring.length < 3) continue;
        final points = [for (final c in ring) projection.project(c)];
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        path.close();
        final fill = familyPaints[family]!.fill;
        final edge = familyPaints[family]!.edge;
        if (fill != null) canvas.drawPath(path, fill);
        if (edge != null) canvas.drawPath(path, edge);

        // Only buildings are labelled. A lot number on every parking apron is
        // the noise that made the campus hard to read in the first place.
        if (family != MapFamily.built) continue;
        final abbreviation = feature.building;
        if (abbreviation == null || abbreviation.isEmpty) continue;
        final bounds = path.getBounds();
        labelCandidates.add((
          text: abbreviation,
          bounds: bounds,
          area: bounds.width * bounds.height,
        ));
      }
    }

    // Nothing built in view, so the loop above never reached the trigger.
    if (!pathsDrawn) _paintPaths(canvas, projection, mapRect, scheme);

    _paintBuildingLabels(canvas, labelCandidates, scheme);
    _paintScaleBar(canvas, projection, mapRect, scheme);

    final pointKinds = {
      for (final feature in features)
        if (feature.geometryType == 'Point') feature.kind,
    };
    // "All places" is an overview, not twelve full pin layers stacked on one
    // another. A selected category gets finer clusters; the mixed overview
    // groups much more aggressively and uses the apps symbol to say that the
    // count contains different kinds of place.
    final clusterCell = pointKinds.length > 1 ? 110.0 : 46.0;
    final buckets =
        <(int, int), List<({CampusMapFeature feature, Offset at})>>{};
    for (final feature in features.where((f) => f.geometryType == 'Point')) {
      final anchor = feature.anchor;
      if (anchor == null) continue;
      final center = projection.project(anchor);
      if (!mapRect.inflate(12).contains(center)) continue;
      final key = (
        (center.dx / clusterCell).floor(),
        (center.dy / clusterCell).floor(),
      );
      buckets.putIfAbsent(key, () => []).add((feature: feature, at: center));
    }

    for (final bucket in buckets.values) {
      final center = Offset(
        bucket.map((item) => item.at.dx).reduce((a, b) => a + b) /
            bucket.length,
        bucket.map((item) => item.at.dy).reduce((a, b) => a + b) /
            bucket.length,
      );
      final selected = bucket.any((item) => item.feature.id == selectedId);
      final eventCount = bucket.fold<int>(0, (total, item) {
        final kind = item.feature.kind;
        return total +
            (kind.startsWith('_event:')
                ? int.tryParse(kind.substring(7)) ?? 1
                : 1);
      });
      final clustered = bucket.length > 1;
      final radius = selected
          ? 18.0
          : clustered
          ? 16.0
          : 13.0;
      final isEvent = bucket.first.feature.kind.startsWith('_event:');
      final foreground = selected || isEvent
          ? scheme.onPrimary
          : scheme.onPrimaryContainer;
      canvas.drawPath(
        _scallop(center, radius),
        Paint()
          ..color = selected || isEvent
              ? scheme.primary
              : scheme.primaryContainer,
      );
      if (clustered || isEvent) {
        final kinds = {for (final item in bucket) item.feature.kind};
        final icon = isEvent
            ? Icons.event_rounded
            : kinds.length == 1
            ? mapPlaceIcon(bucket.first.feature.kind)
            : Icons.apps_rounded;
        _paintMapIcon(
          canvas,
          icon,
          center - const Offset(5.5, 0),
          foreground,
          11,
        );
        _paintMapCount(
          canvas,
          '$eventCount',
          center + const Offset(7, 0),
          foreground,
        );
      } else {
        _paintMapIcon(
          canvas,
          mapPlaceIcon(bucket.single.feature.kind),
          center,
          foreground,
          15,
        );
      }
    }
  }

  /// Building abbreviations, where they fit.
  ///
  /// Without these the map is a field of identical shapes and there is no way
  /// to tell which one is Wallace or Golisano. They are supporting labels, not
  /// a cartographic layer: a label is drawn only when it fits inside its own
  /// building and does not land on one already drawn, and bigger buildings get
  /// first claim, because they are the ones people navigate by.
  /// A scale bar.
  ///
  /// This is only honest because the projection is isotropic. While longitude
  /// was being stretched to fill the window, no single bar could have
  /// described both axes at once.
  ///
  /// It is painted into the canvas rather than laid over it, so it zooms with
  /// the map and keeps telling the truth at every zoom level.
  /// Draws the walking network.
  ///
  /// Measured against the map field rather than eyeballed, and deliberately
  /// not the same role as the parking edge, which would otherwise be the one
  /// other thin grey line on the map:
  ///
  ///                                    light  dark   vs parking edge
  ///   footway (onSurfaceVariant @0.55)  2.74  4.00   1.37 / 1.56
  ///   road    (onSurfaceVariant @0.35)  1.82  2.39   1.10 / 1.07
  ///
  /// Footpaths are drawn more clearly than roads, which is the right way round
  /// on a campus you cross on foot. Roads stay wider and fainter so they read
  /// as context. A road is also a closed-in shape next to a parking outline,
  /// so form separates them where contrast alone is thin.
  void _paintPaths(
    Canvas canvas,
    CampusMapProjection projection,
    Rect mapRect,
    ColorScheme scheme,
  ) {
    if (paths.isEmpty) return;
    final clip = mapRect.inflate(18);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(clip, const Radius.circular(32)));

    void draw(List<List<GeoCoordinate>> ways, Paint paint) {
      for (final way in ways) {
        if (way.length < 2) continue;
        final first = projection.project(way.first);
        final line = Path()..moveTo(first.dx, first.dy);
        for (final point in way.skip(1)) {
          final at = projection.project(point);
          line.lineTo(at.dx, at.dy);
        }
        canvas.drawPath(line, paint);
      }
    }

    draw(
      paths.road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = scheme.onSurfaceVariant.withValues(alpha: 0.35),
    );
    draw(
      paths.foot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = scheme.onSurfaceVariant.withValues(alpha: 0.55),
    );
    canvas.restore();
  }

  void _paintScaleBar(
    Canvas canvas,
    CampusMapProjection projection,
    Rect mapRect,
    ColorScheme scheme,
  ) {
    final latitudeSpan = projection.maxLatitude - projection.minLatitude;
    if (latitudeSpan <= 0 || mapRect.height <= 0) return;
    // A degree of latitude is a constant 111320m, and the longitude axis now
    // carries the same scale, which is what makes one bar meaningful.
    final metresPerPixel = latitudeSpan * 111320 / mapRect.height;

    // Held at a fifth of the *screen*, so zooming in measures a shorter
    // distance more precisely instead of running the bar off the edge.
    final metres = scaleBarMetres(mapRect.width * 0.2 / zoom * metresPerPixel);
    final length = metres / metresPerPixel;
    if (length > mapRect.width * 0.5) return;

    final tick = 3 / zoom;
    final y = mapRect.bottom - 13 / zoom;
    final x = mapRect.left + 13 / zoom;
    final paint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.75)
      ..strokeWidth = 1.4 / zoom
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, y), Offset(x + length, y), paint);
    canvas.drawLine(Offset(x, y - tick), Offset(x, y + tick), paint);
    canvas.drawLine(
      Offset(x + length, y - tick),
      Offset(x + length, y + tick),
      paint,
    );

    final label = TextPainter(
      text: TextSpan(
        text: metres >= 1000 ? '${metres ~/ 1000} km' : '$metres m',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 9 / zoom,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2 / zoom,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(x, y - 5 / zoom - label.height));
  }

  void _paintBuildingLabels(
    Canvas canvas,
    List<({String text, Rect bounds, double area})> candidates,
    ColorScheme scheme,
  ) {
    final ordered = [...candidates]..sort((a, b) => b.area.compareTo(a.area));
    final taken = <Rect>[];

    for (final candidate in ordered) {
      final painter = TextPainter(
        text: TextSpan(
          text: candidate.text,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            // Constant on screen, so zooming in shrinks the label against the
            // building and lets more of them fit. At a fixed size the same
            // handful of labels just grew with everything else, and zooming
            // revealed nothing.
            fontSize: 9 / zoom,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2 / zoom,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Must sit inside the building with a little room, or it reads as a
      // label for whatever is next door.
      if (painter.width + 6 / zoom > candidate.bounds.width ||
          painter.height + 4 / zoom > candidate.bounds.height) {
        continue;
      }

      final rect = Rect.fromCenter(
        center: candidate.bounds.center,
        width: painter.width + 4 / zoom,
        height: painter.height + 2 / zoom,
      );
      if (taken.any(rect.overlaps)) continue;

      taken.add(rect);
      painter.paint(
        canvas,
        candidate.bounds.center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  Path _scallop(Offset center, double radius) {
    final path = Path();
    for (var index = 0; index < 14; index++) {
      final angle = -math.pi / 2 + index * math.pi / 7;
      final currentRadius = index.isEven ? radius : radius * 0.93;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * currentRadius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _paintMapCount(Canvas canvas, String count, Offset center, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: count,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintMapIcon(
    Canvas canvas,
    IconData icon,
    Offset center,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(CampusMapPainter oldDelegate) =>
      oldDelegate.features != features ||
      oldDelegate.boundsFeatures != boundsFeatures ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.scheme != scheme ||
      oldDelegate.zoom != zoom ||
      oldDelegate.paths != paths;

  @override
  bool shouldRebuildSemantics(CampusMapPainter oldDelegate) =>
      oldDelegate.features != features ||
      oldDelegate.boundsFeatures != boundsFeatures ||
      oldDelegate.selectedId != selectedId;
}

/// Names the three outline families.
///
/// Without it the map asks you to infer that a hollow shape is a car park and
/// an olive one is grass. The swatches are painted with `mapFamilyPaints`, the
/// same function the map uses, so the legend cannot describe colours the map
/// is not drawing.
class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: Shapes.inner,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _entry(MapFamily.built, 'Building'),
            const SizedBox(height: 5),
            _entry(MapFamily.parking, 'Parking'),
            const SizedBox(height: 5),
            _entry(MapFamily.open, 'Green space'),
            const SizedBox(height: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.apps_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 7),
                Text(
                  'Number = grouped places',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry(MapFamily family, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CustomPaint(
        size: const Size(15, 10),
        painter: _LegendSwatch(family: family, scheme: scheme),
      ),
      const SizedBox(width: 7),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _LegendSwatch extends CustomPainter {
  const _LegendSwatch({required this.family, required this.scheme});

  final MapFamily family;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final paints = mapFamilyPaints(family, scheme);
    final rect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final fill = paints.fill;
    final edge = paints.edge;
    if (fill != null) canvas.drawRect(rect, fill);
    if (edge != null) canvas.drawRect(rect, edge);
  }

  @override
  bool shouldRepaint(_LegendSwatch old) =>
      old.family != family || old.scheme != scheme;
}
