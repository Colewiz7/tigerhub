/// Offline campus map painted directly from cached GeoJSON.
///
/// No tiles, API key, or map dependency. The horizontal place list is the
/// keyboard and screen-reader equivalent of tapping pins on the canvas.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  String? _kind;
  int? _selectedId;
  bool _showEvents = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
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
                builder: (context, constraints) => InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final projection = CampusMapProjection(
                        mapFeatures,
                        Size(constraints.maxWidth, constraints.maxHeight),
                        boundsFeatures: all,
                      );
                      final hit = projection.nearest(details.localPosition);
                      if (hit != null) setState(() => _selectedId = hit.id);
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: CampusMapPainter(
                        features: mapFeatures,
                        boundsFeatures: all,
                        selectedId: _selectedId,
                        scheme: Theme.of(context).colorScheme,
                      ),
                    ),
                  ),
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kinds.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Filter map places',
            onSelected: (value) => onKindChanged(value.isEmpty ? null : value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: '', child: Text('All places')),
              for (final entry in kinds.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
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
                    const Icon(Icons.tune_rounded, size: 19),
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
                    feature.where.isEmpty ? feature.kindName : feature.where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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

class CampusMapProjection {
  CampusMapProjection(
    this.features,
    this.size, {
    List<CampusMapFeature>? boundsFeatures,
  }) {
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
      return (anchor.longitude - medianLongitude).abs() <= 0.03 &&
          (anchor.latitude - medianLatitude).abs() <= 0.025;
    });
    final points = core.expand((f) => f.coordinates.expand((ring) => ring));
    if (points.isEmpty) return;
    minLongitude = points.map((p) => p.longitude).reduce(math.min);
    maxLongitude = points.map((p) => p.longitude).reduce(math.max);
    minLatitude = points.map((p) => p.latitude).reduce(math.min);
    maxLatitude = points.map((p) => p.latitude).reduce(math.max);
  }

  final List<CampusMapFeature> features;
  final Size size;
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

  Rect get mapRect {
    final longitudeSpan = math.max(maxLongitude - minLongitude, 0.000001);
    final latitudeSpan = math.max(maxLatitude - minLatitude, 0.000001);
    final latitudeRadians = ((minLatitude + maxLatitude) / 2) * math.pi / 180;
    final geographicWidth = longitudeSpan * math.cos(latitudeRadians);
    final availableWidth = math.max(size.width - padding * 2, 1);
    final availableHeight = math.max(size.height - padding * 2, 1);
    final scale = math.min(
      availableWidth / geographicWidth,
      availableHeight / latitudeSpan,
    );
    final width = geographicWidth * scale;
    final height = latitudeSpan * scale;
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
    for (final feature in features) {
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

class CampusMapPainter extends CustomPainter {
  CampusMapPainter({
    required this.features,
    this.boundsFeatures,
    required this.selectedId,
    required this.scheme,
  });

  final List<CampusMapFeature> features;
  final List<CampusMapFeature>? boundsFeatures;
  final int? selectedId;
  final ColorScheme scheme;

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
    canvas.drawRRect(
      RRect.fromRectAndRadius(mapRect.inflate(18), const Radius.circular(32)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = scheme.primary.withValues(alpha: 0.12),
    );

    final polygonFill = Paint()..color = scheme.surfaceContainerHigh;
    final polygonEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = scheme.primary.withValues(alpha: 0.42);

    for (final feature in features.where((f) => f.geometryType != 'Point')) {
      for (final ring in feature.coordinates) {
        if (ring.length < 3) continue;
        final path = Path()
          ..moveTo(
            projection.project(ring.first).dx,
            projection.project(ring.first).dy,
          );
        for (final coordinate in ring.skip(1)) {
          final point = projection.project(coordinate);
          path.lineTo(point.dx, point.dy);
        }
        path.close();
        canvas.drawPath(path, polygonFill);
        canvas.drawPath(path, polygonEdge);
      }
    }

    final buckets =
        <(int, int), List<({CampusMapFeature feature, Offset at})>>{};
    for (final feature in features.where((f) => f.geometryType == 'Point')) {
      final anchor = feature.anchor;
      if (anchor == null) continue;
      final center = projection.project(anchor);
      final key = ((center.dx / 30).floor(), (center.dy / 30).floor());
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
          ? 15.0
          : clustered
          ? 12.0
          : 8.0;
      canvas.drawPath(
        _scallop(center, radius),
        Paint()
          ..color = selected || bucket.first.feature.kind.startsWith('_event:')
              ? scheme.primary
              : scheme.primaryContainer,
      );
      if (clustered || bucket.first.feature.kind.startsWith('_event:')) {
        final label = TextPainter(
          text: TextSpan(
            text: '$eventCount',
            style: TextStyle(
              color: selected || bucket.first.feature.kind.startsWith('_event:')
                  ? scheme.onPrimary
                  : scheme.onPrimaryContainer,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
      } else {
        canvas.drawCircle(
          center,
          selected ? 3 : 2,
          Paint()
            ..color = selected ? scheme.onPrimary : scheme.onPrimaryContainer,
        );
      }
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

  @override
  bool shouldRepaint(CampusMapPainter oldDelegate) =>
      oldDelegate.features != features ||
      oldDelegate.boundsFeatures != boundsFeatures ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.scheme != scheme;
}
