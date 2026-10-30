/// Offline campus map painted directly from cached GeoJSON.
///
/// No tiles, API key, or map dependency. The horizontal place list is the
/// keyboard and screen-reader equivalent of tapping pins on the canvas.
library;

import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/campus_paths.dart';
import '../data/osm_features.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/frame_monitor.dart';
import '../services/frame_stats.dart' show frameTabMap;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
import 'campus_event_mapper.dart';
import 'empty_state.dart';
import 'freshness.dart';
import 'map_labels.dart';
import 'map_pin.dart';
import 'map_style.dart';
import 'osm_geometry.dart';
import 'search_field.dart';
import 'segmented_picker.dart';

/// Pin counts are text too, so they hold the 11 pt floor.
const double mapCountSize = 11;

const double _maxMapZoom = 20;
const double _mapPanMargin = 80;

/// An OpenStreetMap door this close to an RIT entrance pin is the same door.
const double _sameDoorMetres = 5;

/// Entrance dot size on screen: a 6 pt dot inside a 1 pt outline.
const double _entranceDot = 6;
const double _entranceRing = 1;

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
  Size _viewportSize = Size.zero;

  /// Empty until the bundled asset decodes. The map paints without it, then
  /// again with it, rather than holding the whole screen back for 114 KB.
  CampusPaths _paths = const CampusPaths.empty();

  /// The same for the water, parks and other OpenStreetMap layers.
  OsmFeatures _osm = const OsmFeatures.empty();

  @override
  void initState() {
    super.initState();
    CampusPaths.load().then((paths) {
      if (mounted) setState(() => _paths = paths);
    });
    OsmFeatures.load().then((osm) {
      if (mounted) setState(() => _osm = osm);
    });
  }

  /// Pan and zoom are gestures, not scrolls, so the frame stats are told.
  /// Balanced however the gestures overlap, and closed if the map goes away
  /// mid gesture.
  bool _interacting = false;

  void _markInteraction(bool start) {
    if (start == _interacting) return;
    _interacting = start;
    if (start) {
      FrameMonitor.instance.scrollStarted(frameTabMap);
    } else {
      FrameMonitor.instance.scrollEnded();
    }
  }

  @override
  void dispose() {
    _markInteraction(false);
    _transform.dispose();
    _mapFocus.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    final matrix = _transform.value;
    final current = matrix.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, _maxMapZoom);
    final applied = target / current;
    if (applied == 1) return;
    final focus = _viewportSize.isEmpty
        ? Offset.zero
        : _viewportSize.center(Offset.zero);
    final translatedX = focus.dx - applied * (focus.dx - matrix.entry(0, 3));
    final translatedY = focus.dy - applied * (focus.dy - matrix.entry(1, 3));
    _transform.value = _clampedTransform(target, translatedX, translatedY);
  }

  Matrix4 _clampedTransform(double scale, double tx, double ty) {
    final minX = _viewportSize.width * (1 - scale) - _mapPanMargin;
    final minY = _viewportSize.height * (1 - scale) - _mapPanMargin;
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx.clamp(minX, _mapPanMargin))
      ..setEntry(1, 3, ty.clamp(minY, _mapPanMargin));
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

  Future<void> _searchPlaces(
    List<CampusMapFeature> all,
    List<CampusMapFeature> backdrop, {
    bool focusField = false,
  }) async {
    final searchable = [
      for (final feature in all)
        if ((feature.geometryType == 'Point' &&
                !feature.kind.startsWith('_')) ||
            (feature.kind == '_campus' && feature.building != null))
          feature,
    ];
    final feature = await Navigator.of(context).push<CampusMapFeature>(
      MaterialPageRoute(
        builder: (_) => _MapSearchPage(features: searchable, focusField: focusField),
      ),
    );
    if (feature == null || !mounted) return;
    setState(() {
      _showEvents = false;
      _kind = feature.kind == '_campus' ? null : feature.kind;
      _selectedId = feature.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewportSize.isEmpty) return;
      final projection = CampusMapProjection(
        [...backdrop, feature],
        _viewportSize,
        boundsFeatures: all,
      );
      final anchor = feature.anchor;
      if (anchor == null) return;
      final point = projection.project(anchor);
      const scale = 2.4;
      _transform.value = _clampedTransform(
        scale,
        _viewportSize.width / 2 - point.dx * scale,
        _viewportSize.height / 2 - point.dy * scale,
      );
    });
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
        title: 'Map unavailable',
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
    final selectedBuilding = backdrop
        .where((feature) => feature.id == _selectedId)
        .firstOrNull;
    final selectedEvent = eventMap.groups
        .where((group) => group.id == _selectedId)
        .firstOrNull;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchPlaces(all, backdrop, focusField: true),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final mode = SegmentedPicker<bool>(
                value: _showEvents,
                labels: const {false: 'Places', true: 'Events'},
                onChanged: (events) => setState(() {
                  _showEvents = events;
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
                onSearch: () => _searchPlaces(all, backdrop),
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
                color: MapPalette.of(
                  Theme.of(context).colorScheme.brightness,
                ).ground,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _viewportSize = constraints.biggest;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Semantics(
                            container: true,
                            label:
                                'Interactive campus map. Use plus and minus to '
                                'zoom, or Control F to search.',
                            child: Focus(
                              focusNode: _mapFocus,
                              onKeyEvent: _handleMapKey,
                              child: ValueListenableBuilder<Matrix4>(
                                valueListenable: _transform,
                                builder: (context, matrix, child) =>
                                    InteractiveViewer(
                                      transformationController: _transform,
                                      onInteractionStart: (_) =>
                                          _markInteraction(true),
                                      onInteractionEnd: (_) =>
                                          _markInteraction(false),
                                      minScale: 1,
                                      maxScale: _maxMapZoom,
                                      boundaryMargin: EdgeInsets.all(
                                        _mapPanMargin /
                                            matrix.getMaxScaleOnAxis(),
                                      ),
                                      child: child!,
                                    ),
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
                                      zoom: _transform.value
                                          .getMaxScaleOnAxis(),
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
                                    // Its own layer, so a pan is the compositor
                                    // moving a finished raster rather than Skia
                                    // redrawing 191 outlines and the whole walking
                                    // network for every frame of the gesture.
                                    builder: (context, matrix, _) =>
                                        RepaintBoundary(
                                          child: CustomPaint(
                                            size: Size(
                                              constraints.maxWidth,
                                              constraints.maxHeight,
                                            ),
                                            painter: CampusMapPainter(
                                              features: mapFeatures,
                                              boundsFeatures: all,
                                              selectedId: _selectedId,
                                              scheme: Theme.of(context)
                                                  .colorScheme,
                                              platform: Theme.of(context).platform,
                                              zoom: matrix.getMaxScaleOnAxis(),
                                              paths: _paths,
                                              osm: _osm,
                                              onSelect: (feature) => setState(
                                                () => _selectedId = feature.id,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Fixed, and outside the InteractiveViewer, so it does not
                        // zoom the way the scale bar deliberately does.
                        // wraps short of the north indicator
                        Positioned(
                          left: 12,
                          top: 12,
                          right: 12 + _NorthIndicator.size + 8,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: _MapLegend(
                              scheme: Theme.of(context).colorScheme,
                            ),
                          ),
                        ),
                        const Positioned(
                          right: 12,
                          top: 12,
                          child: _NorthIndicator(),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: ValueListenableBuilder<Matrix4>(
                            valueListenable: _transform,
                            builder: (context, matrix, _) => _MapZoomControls(
                              zoom: matrix.getMaxScaleOnAxis(),
                              onZoomIn: () => _zoomBy(1.5),
                              onZoomOut: () => _zoomBy(1 / 1.5),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // a strip is a fixed row of cards, a selected panel grows with its text
          ConstrainedBox(
            constraints:
                selected == null &&
                    selectedBuilding == null &&
                    selectedEvent == null
                ? BoxConstraints.tightFor(height: _stripHeight(context, events: _showEvents))
                : BoxConstraints(minHeight: 146, maxHeight: selectedEvent == null ? _placePanelMax(context) : _eventPanelHeight(context)),
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
                : selected == null && selectedBuilding == null
                ? _kind == null
                      ? _KindStrip(
                          features: visible,
                          onSelect: (kind) => setState(() {
                            _kind = kind;
                            _selectedId = null;
                            _transform.value = Matrix4.identity();
                          }),
                        )
                      : _PlaceStrip(
                          features: visible,
                          selectedId: _selectedId,
                          onSelect: (feature) =>
                              setState(() => _selectedId = feature.id),
                        )
                : _SelectedPlace(
                    feature: selected ?? selectedBuilding!,
                    onClose: () => setState(() => _selectedId = null),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NorthIndicator extends StatelessWidget {
  const _NorthIndicator();

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final map = MapPalette.of(Theme.of(context).brightness);
    return Semantics(
      label: 'Map is oriented north up',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'North up',
          child: Material(
            color: map.chrome.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    AppIconKind.navigation.of(context),
                    size: 25,
                    color: map.chromeAccent,
                  ),
                  Positioned(
                    bottom: 3,
                    child: Text(
                      'N',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: map.chromeInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final map = MapPalette.of(Theme.of(context).brightness);
    final ink = Theme.of(context).textTheme.bodyMedium?.copyWith(color: map.chromeInk);
    final inkButton = IconButton.styleFrom(
      foregroundColor: map.chromeMuted,
      disabledForegroundColor: map.chromeInk.withValues(alpha: 0.38),
    );
    // the hint takes its own row when both dont fit
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (zoom < 1.15)
          Material(
            color: map.chrome.withValues(alpha: 0.92),
            // a pill on one line, rounded when the text wraps
            borderRadius: Shapes.inner,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIconKind.route.of(context), size: 16, color: map.chromeAccent),
                  const SizedBox(width: 7),
                  Flexible(child: Text('Zoom in for walking paths', style: ink)),
                ],
              ),
            ),
          ),
        Material(
          color: map.chrome.withValues(alpha: 0.92),
          borderRadius: Shapes.inner,
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Zoom out',
                onPressed: zoom > 1.01 ? onZoomOut : null,
                style: inkButton,
                icon: Icon(AppIconKind.minus.of(context)),
              ),
              SizedBox(
                width: 38,
                // one line, shrunk to fit at large text
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${zoom.toStringAsFixed(1).replaceFirst('.0', '')}×',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: map.chromeInk),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: zoom < _maxMapZoom - 0.01 ? onZoomIn : null,
                style: inkButton,
                icon: Icon(AppIconKind.add.of(context)),
              ),
            ],
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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                                    ? group.events.single.displayTitle
                                    : '${group.events.length} events',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                group.building,
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              shrinkWrap: true,
              itemCount: group.events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final event = group.events[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.displayTitle,
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
            icon: Icon(AppIconKind.close.of(context)),
          ),
        ],
      ),
    ),
  );
}

// no autofocus, the keyboard waits for a tap on the field
class _MapSearchPage extends StatefulWidget {
  const _MapSearchPage({required this.features, required this.focusField});

  final List<CampusMapFeature> features;
  final bool focusField;

  @override
  State<_MapSearchPage> createState() => _MapSearchPageState();
}

class _MapSearchPageState extends State<_MapSearchPage> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // ctrl+f asked for the field, the search button didnt
    if (widget.focusField) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<CampusMapFeature> get _matches {
    final needle = _query.text.trim().toLowerCase();
    final features = widget.features;
    final matches = features.where((feature) {
      final haystack = [
        feature.name,
        feature.kindName,
        feature.building ?? '',
        feature.room ?? '',
        feature.note ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();
    int score(CampusMapFeature feature) {
      if (needle.isEmpty) return 3;
      final name = feature.name.toLowerCase();
      final building = (feature.building ?? '').toLowerCase();
      if (name == needle || building == needle) return 0;
      if (name.startsWith(needle) || building.startsWith(needle)) return 1;
      return 2;
    }

    matches.sort((a, b) {
      final ranked = score(a).compareTo(score(b));
      return ranked != 0 ? ranked : a.name.compareTo(b.name);
    });
    return matches.take(30).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to map',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(AppIconKind.back.of(context)),
                ),
                Expanded(
                  child: SearchField(
                    controller: _query,
                    focusNode: _focus,
                    hintText: 'Building, room, or campus place',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _results(context)),
        ],
      ),
    ),
  );

  Widget _results(BuildContext context) {
    final matches = _matches;
    if (matches.isEmpty) {
      return const Center(child: Text('No campus places match that search.'));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final feature = matches[index];
        final location = feature.where;
        final isBuilding = feature.kind == '_campus';
        final palette = mapPinPalette(
          feature.kind,
          Theme.of(context).brightness,
        );
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: palette.$1,
            foregroundColor: palette.$2,
            child: Icon(mapPlaceIcon(feature.kind).of(context)),
          ),
          title: Text(feature.name),
          subtitle: Text(
            isBuilding
                ? '${feature.kindName} · ${feature.building}'
                : location.isEmpty
                ? feature.kindName
                : '${feature.kindName} · $location',
          ),
          onTap: () => Navigator.of(context).pop(feature),
        );
      },
    );
  }
}

class _MapToolbar extends StatelessWidget {
  const _MapToolbar({
    required this.kinds,
    required this.selectedKind,
    required this.onKindChanged,
    required this.onFit,
    required this.onSearch,
  });

  final Map<String, String> kinds;
  final String? selectedKind;
  final ValueChanged<String?> onKindChanged;
  final VoidCallback onFit;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedLabel = selectedKind == null
        ? 'All places'
        : kinds[selectedKind] ?? 'All places';
    final selectedIcon = selectedKind == null
        ? AppIconKind.allPlaces
        : mapPlaceIcon(selectedKind!);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Search campus places (Ctrl+F)',
          onPressed: onSearch,
          icon: Icon(AppIconKind.search.of(context)),
        ),
        const SizedBox(width: 8),
        // the filter gives way first, the round buttons keep their 48
        if (kinds.isNotEmpty)
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: 'Filter map places',
              onSelected: (value) => onKindChanged(value.isEmpty ? null : value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: '',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppIconKind.allPlaces.of(context)),
                    title: Text('All places'),
                  ),
                ),
                for (final entry
                    in kinds.entries.toList()
                      ..sort((a, b) => a.value.compareTo(b.value)))
                  PopupMenuItem(
                    value: entry.key,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(mapPlaceIcon(entry.key).of(context)),
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
                      Icon(selectedIcon.of(context), size: 19),
                      const SizedBox(width: 8),
                      Flexible(child: Text(selectedLabel)),
                      const SizedBox(width: 4),
                      Icon(AppIconKind.expand.of(context), size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Fit campus',
          onPressed: onFit,
          icon: Icon(AppIconKind.recenter.of(context)),
        ),
      ],
    );
  }
}

double _lines(BuildContext context, TextStyle? style, int count) {
  final painter = TextPainter(
    text: TextSpan(text: List.filled(count, 'Ag').join('\n'), style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: TextDirection.ltr,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

// past a third of the screen the details scroll, the map keeps the rest
double _placePanelMax(BuildContext context) => math.max(146.0, MediaQuery.sizeOf(context).height / 3).floorToDouble();

// two events show at once, more scroll, never under 146
double _eventPanelHeight(BuildContext context) {
  final text = Theme.of(context).textTheme;
  final event = _lines(context, text.titleSmall, 1) + _lines(context, text.bodySmall, 1);
  return math.max(146.0, 20 + event * 2 + 6).ceilToDouble();
}

// tall enough for the tallest strip card at this text size, never under 92
double _stripHeight(BuildContext context, {required bool events}) {
  final text = Theme.of(context).textTheme;
  double lines(TextStyle? style, int count) => _lines(context, style, count);

  if (events) {
    // the mapped count line is held to two
    return math.max(92.0, lines(text.bodySmall, 2) + 6 + 16 + lines(text.titleSmall, 1) + 3 + lines(text.bodySmall, 1)).ceilToDouble();
  }
  final kinds = 16 + math.max(38.0, lines(text.titleSmall?.copyWith(height: 1.05), 2) + 3 + lines(text.bodySmall, 1));
  final places = 20 + math.max(38.0, lines(text.titleSmall, 2) + 3 + lines(text.bodySmall, 1));
  return [92.0, kinds, places].reduce(math.max).ceilToDouble();
}

class _KindStrip extends StatelessWidget {
  const _KindStrip({required this.features, required this.onSelect});

  final List<CampusMapFeature> features;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final groups = <String, ({String name, int count})>{};
    for (final feature in features) {
      final previous = groups[feature.kind];
      groups[feature.kind] = (
        name: feature.kindName,
        count: (previous?.count ?? 0) + 1,
      );
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      scrollDirection: Axis.horizontal,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final scheme = Theme.of(context).colorScheme;
        final palette = mapPinPalette(entry.key, scheme.brightness);
        return SizedBox(
          width: 236,
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: Shapes.inner,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelect(entry.key),
              canRequestFocus: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: palette.$1,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(mapPlaceIcon(entry.key), size: 20, color: palette.$2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(height: 1.05),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${entry.value.count} '
                            '${entry.value.count == 1 ? 'place' : 'places'}',
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
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    scrollDirection: Axis.horizontal,
    itemCount: features.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (context, index) {
      final feature = features[index];
      return SizedBox(
        width: 236,
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
                          maxLines: 2,
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
          _PlaceCategoryMark(feature: feature, size: 46, iconSize: 21),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    feature.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    feature.kindName,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.primary),
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
          ),
          IconButton(
            tooltip: 'Close details',
            onPressed: onClose,
            icon: Icon(AppIconKind.close.of(context)),
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
    this.iconSize = 17,
  });

  final CampusMapFeature feature;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final map = MapPalette.of(Theme.of(context).brightness);
    return Semantics(
      label: feature.kindName,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: map.pinPlace,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AppIcon(mapPlaceIcon(feature.kind), size: iconSize, color: map.onPinPlace),
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

  CampusMapFeature? nearest(Offset position, {double zoom = 1}) {
    CampusMapFeature? nearestFeature;
    var nearestDistance = 28.0 / zoom;
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

/// How a campus outline is drawn, and what it is.
///
/// maps.rit.edu names the sub-category each outline came from, so a parking
/// apron, a lecture hall and a dorm arrive already distinguishable. They used
/// to be painted identically, and since lots are large they read as enormous
/// buildings and buried the campus they surround.
///
/// The built kinds all share rank 2: they are drawn last, on top of the ground
/// and the paths, and differ only in colour.
enum MapFamily {
  /// Quads, gardens, solar fields. Ground, not structure.
  open(0, 'Green space'),

  /// Lots and aprons. Context you cross, not somewhere you go.
  parking(1, 'Parking'),

  academic(2, 'Academic'),
  residential(2, 'Residential'),
  athletic(2, 'Athletic'),
  dining(2, 'Dining'),
  otherBuilt(2, 'Other building');

  const MapFamily(this.rank, this.label);

  /// Painting order, ground upward.
  final int rank;

  /// What the legend calls it.
  final String label;

  /// Anything you can walk into.
  bool get isBuilt => rank == 2;
}

/// Familiar, distinct symbols shared by the map, filters, and place cards.
AppIconKind mapPlaceIcon(String kind) => switch (kind) {
  '_campus' => AppIconKind.campus,
  'water' => AppIconKind.water,
  'ev_charge' => AppIconKind.evCharge,
  'blue_light' => AppIconKind.blueLight,
  'aed' => AppIconKind.aed,
  'restroom_all_gender' => AppIconKind.restroom,
  'restroom_accessible' => AppIconKind.accessible,
  'atm' => AppIconKind.atm,
  'changing_table' => AppIconKind.changingTable,
  'entrance_accessible' => AppIconKind.accessibleEntrance,
  'bus_stop' => AppIconKind.shuttle,
  'bike_rack' => AppIconKind.bike,
  'reload' => AppIconKind.reload,
  'time_clock' => AppIconKind.timeClock,
  'printer' => AppIconKind.printer,
  'study_area' => AppIconKind.study,
  'computer_lab' => AppIconKind.computer,
  'connection_hub' => AppIconKind.hub,
  'lactation' => AppIconKind.lactation,
  'vending' => AppIconKind.drink,
  'convenience' => AppIconKind.market,
  'food_share' => AppIconKind.volunteer,
  'bottle_return' => AppIconKind.recycling,
  'support_services' => AppIconKind.support,
  'higi_kiosk' => AppIconKind.aed,
  'gym' => AppIconKind.gym,
  _ when kind.startsWith('_event:') => AppIconKind.event,
  _ => AppIconKind.place,
};

(Color, Color) mapPinPalette(String kind, Brightness brightness) {
  final map = MapPalette.of(brightness);
  return switch (kind) {
    'water' || 'ev_charge' || 'bus_stop' || 'bike_rack' => (map.pinUtility, map.onPinUtility),
    'aed' || 'blue_light' || 'restroom_accessible' || 'entrance_accessible' => (map.pinSafety, map.onPinSafety),
    _ => (map.pinPlace, map.onPinPlace),
  };
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
  if (name.contains('residential')) return MapFamily.residential;
  if (name.contains('academic')) return MapFamily.academic;
  if (name.contains('athletic')) return MapFamily.athletic;
  if (name.contains('restaurant') || name.contains('dining')) {
    return MapFamily.dining;
  }
  return MapFamily.otherBuilt;
}

/// The monochrome glyph that carries the category when colour cannot: it
/// shows beside building labels from [mapGlyphMinZoom].
AppIconKind mapGlyph(MapFamily family) => switch (family) {
  MapFamily.academic => AppIconKind.school,
  MapFamily.residential => AppIconKind.housing,
  MapFamily.athletic => AppIconKind.gym,
  MapFamily.dining => AppIconKind.dining,
  _ => AppIconKind.buildings,
};

MapCategory? mapCategory(MapFamily family) => switch (family) {
  MapFamily.academic => MapCategory.academic,
  MapFamily.residential => MapCategory.residential,
  MapFamily.athletic => MapCategory.athletic,
  MapFamily.dining => MapCategory.dining,
  MapFamily.otherBuilt => MapCategory.other,
  _ => null,
};

List<double> _fillSchedule(MapFamily family) => switch (family) {
  MapFamily.open => MapSchedule.grass,
  MapFamily.parking => MapSchedule.parking,
  MapFamily.otherBuilt => MapSchedule.otherBuilding,
  _ => MapSchedule.building,
};

Color _faded(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity);

/// Fill and edge for one family at one zoom, from the fixed palette.
///
/// A null paint is a layer that is fully faded out. Stroke widths are screen
/// points; the painter divides them by the zoom.
({Paint? fill, Paint? edge}) mapFamilyPaints(
  MapFamily family,
  ColorScheme scheme, {
  double zoom = MapSchedule.legendZoom,
}) {
  final palette = MapPalette.of(scheme.brightness);
  final opacity = opacityAt(_fillSchedule(family), zoom);
  if (opacity <= 0) return (fill: null, edge: null);
  switch (family) {
    case MapFamily.open:
      return (
        fill: Paint()..color = _faded(palette.grass, opacity),
        edge: null,
      );
    case MapFamily.parking:
      return (
        fill: Paint()..color = _faded(palette.parking, opacity),
        edge: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = _faded(palette.parkingStroke, opacity),
      );
    default:
      final category = mapCategory(family)!;
      return (
        fill: Paint()..color = _faded(palette.fill(category), opacity),
        edge: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = _faded(palette.buildingOutline, opacity),
      );
  }
}

/// Fill and 0.75 pt edge for OpenStreetMap water at one zoom. Shared by the
/// map and the legend swatch, like [mapFamilyPaints].
({Paint? fill, Paint? edge}) mapWaterPaints(
  ColorScheme scheme, {
  double zoom = MapSchedule.legendZoom,
}) {
  final palette = MapPalette.of(scheme.brightness);
  final opacity = opacityAt(MapSchedule.water, zoom);
  if (opacity <= 0) return (fill: null, edge: null);
  return (
    fill: Paint()..color = _faded(palette.water, opacity),
    edge: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = _faded(palette.waterOutline, opacity),
  );
}

/// The edge of a sports pitch: the parking stroke, on the green schedule, so
/// a pitch reads as green space with a rule round it.
Paint? mapPitchEdge(ColorScheme scheme, {double zoom = 1}) {
  final opacity = opacityAt(MapSchedule.grass, zoom);
  if (opacity <= 0) return null;
  return Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.75
    ..color = _faded(MapPalette.of(scheme.brightness).parkingStroke, opacity);
}

/// Same length and the same feature objects in the same order. A replaced
/// feature misses, which costs a rebuild and is never wrong.
bool _sameFeatures(List<CampusMapFeature>? a, List<CampusMapFeature>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

class CampusMapPainter extends CustomPainter {
  CampusMapPainter({
    required this.features,
    this.boundsFeatures,
    required this.selectedId,
    required this.scheme,
    this.platform = TargetPlatform.android,
    this.onSelect,
    this.zoom = 1,
    this.paths = const CampusPaths.empty(),
    this.osm = const OsmFeatures.empty(),
  });

  final List<CampusMapFeature> features;
  final List<CampusMapFeature>? boundsFeatures;
  final int? selectedId;
  final ColorScheme scheme;

  /// Picks the marker glyphs, Cupertino on iOS.
  final TargetPlatform platform;
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

  /// The bundled OpenStreetMap water, parks and pitches. Drawn under RIT's own
  /// shapes. Empty until the asset loads, and empty forever if it fails.
  final OsmFeatures osm;

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
              radius: 24 / zoom,
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
    // reaches past the canvas so a pan never exposes the layer behind
    final ground = (Offset.zero & size).inflate(_mapPanMargin);
    final palette = MapPalette.of(scheme.brightness);
    canvas.drawRect(ground, Paint()..color = palette.ground);

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
      ..color = palette.entrance.withValues(alpha: 0.035);
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
        ..color = palette.entrance.withValues(alpha: 0.12),
    );

    // Drawn from the ground up, so the things you actually walk into sit on
    // top. The paints come from the same function as the legend swatches, at
    // this zoom, so a layer that has faded out is skipped rather than drawn
    // at zero alpha.
    final familyPaints = {
      for (final family in MapFamily.values)
        family: mapFamilyPaints(family, scheme, zoom: zoom),
    };

    // Collected while the polygons are drawn, so a label knows the shape it
    // belongs to and can be skipped when it will not fit inside it.
    final geometry = _geometryFor(projection);

    void drawFamily(MapFamily family) {
      final path = geometry.areas[family];
      if (path == null) return;
      final fill = familyPaints[family]!.fill;
      final edge = familyPaints[family]!.edge;
      if (fill != null) canvas.drawPath(path, fill);
      if (edge != null) {
        // Keep outlines cartographic as the viewer zooms instead of turning
        // them into thick neon borders.
        edge.strokeWidth /= zoom;
        canvas.drawPath(path, edge);
      }
    }

    // Ground first, then the paths crossing it, then what you walk into.
    // OpenStreetMap water and green sit under RIT's own shapes.
    _paintOsmGround(canvas, geometry, familyPaints[MapFamily.open]!.fill);
    drawFamily(MapFamily.open);
    drawFamily(MapFamily.parking);
    _paintPaths(canvas, geometry, ground);
    _paintOsmBuildings(canvas, geometry);
    for (final family in MapFamily.values.where((family) => family.isBuilt)) {
      drawFamily(family);
    }
    _paintEntrances(canvas, geometry);

    final selectedBuilding = features
        .where(
          (feature) =>
              feature.id == selectedId && feature.geometryType != 'Point',
        )
        .firstOrNull;
    if (selectedBuilding != null) {
      final outline = Path();
      for (final ring in selectedBuilding.coordinates) {
        if (ring.length < 3) continue;
        outline.addPolygon([
          for (final coordinate in ring) projection.project(coordinate),
        ], true);
      }
      // tonal overlay and a solid outline, no glow, blur or shadow
      canvas.drawPath(outline, Paint()..color = palette.selectedOverlay);
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 / zoom
          ..strokeJoin = StrokeJoin.round
          ..color = palette.selectedOutline,
      );
    }

    final buckets = geometry.pinBucketsAt(zoom);
    _paintLabels(canvas, geometry, buckets);
    _paintScaleBar(canvas, projection, mapRect, scheme);

    // "All places" is a category chooser, not a heat map. Almost every kind
    // is concentrated in the academic core, so showing all twelve at once
    // creates a misleading knot. The icon cards below provide the overview;
    // spatial markers appear after the reader chooses a category.
    for (final pinBucket
        in geometry.categoryOverview ? const <_PinBucket>[] : buckets) {
      final bucket = pinBucket.items;
      final center = pinBucket.center;
      final selected = bucket.any((item) => item.feature.id == selectedId);
      final eventCount = bucket.fold<int>(0, (total, item) {
        final kind = item.feature.kind;
        return total +
            (kind.startsWith('_event:')
                ? int.tryParse(kind.substring(7)) ?? 1
                : 1);
      });
      final clustered = bucket.length > 1;
      final isEvent = bucket.first.feature.kind.startsWith('_event:');
      final counted = clustered || isEvent;
      // screen points: 22 single, 30 selected, 30 or 34 with a count
      final radius = _pinRadius(pinBucket, selected) / zoom;
      final accent = selected || counted;
      final fill = accent ? palette.clusterBadge : palette.labelInk;
      final foreground = accent ? palette.clusterBadgeText : palette.ground;
      final shape = scallopPath(center, radius);
      canvas.drawPath(shape, Paint()..color = fill);
      if (selected) {
        canvas.drawPath(
          shape,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / zoom
            ..strokeJoin = StrokeJoin.round
            ..color = palette.selectedOutline,
        );
      }
      if (counted) {
        final kinds = {for (final item in bucket) item.feature.kind};
        final icon = isEvent
            ? AppIconKind.event
            : kinds.length == 1
            ? mapPlaceIcon(bucket.first.feature.kind)
            : AppIconKind.allPlaces;
        final count = _countPainter('$eventCount', foreground);
        // the icon yields to the number when the two do not fit the badge
        const iconSize = 11.0;
        const gap = 2.0;
        final withIcon = count.width + iconSize + gap <= radius * zoom * 2 * 0.84;
        final total = withIcon ? count.width + iconSize + gap : count.width;
        final left = -total / 2;
        if (withIcon) {
          _paintMapIcon(
            canvas,
            icon.on(platform),
            center + Offset((left + iconSize / 2) / zoom, 0),
            foreground,
            iconSize / zoom,
          );
        }
        final countCenter = withIcon
            ? left + iconSize + gap + count.width / 2
            : 0.0;
        _paintCount(canvas, count, center + Offset(countCenter / zoom, 0), zoom);
      } else {
        _paintMapIcon(
          canvas,
          mapPlaceIcon(bucket.single.feature.kind).on(platform),
          center,
          foreground,
          (selected ? 15 : 13) / zoom,
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
  /// Draws the walking network from the palette, faded in by the zoom
  /// schedule: roads from 1x, footpaths from 3x.
  void _paintPaths(Canvas canvas, _MapGeometry geometry, Rect ground) {
    if (paths.isEmpty) return;
    canvas.save();
    canvas.clipRect(ground);
    // Roads get a casing and centre stroke, like an actual campus map. At the
    // overview scale the dense footway graph is withheld; it fades into the
    // job only when zooming makes those choices useful.
    final palette = MapPalette.of(scheme.brightness);
    Paint line(double width, Color color, double opacity) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width / zoom
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _faded(color, opacity);
    final roads = opacityAt(MapSchedule.roads, zoom);
    if (roads > 0) {
      // local road: 3.5 pt casing under a 2.0 pt core. The bundled network
      // carries no road class, so every way gets the local construction.
      canvas.drawPath(geometry.road, line(3.5, palette.roadCasing, roads));
      canvas.drawPath(geometry.road, line(2.0, palette.roadCore, roads));
    }
    final foot = opacityAt(MapSchedule.footpaths, zoom);
    if (foot > 0) {
      canvas.drawPath(geometry.foot, line(1.25, palette.footpath, foot));
    }
    canvas.restore();
  }

  /// Water, then green space and pitches, from the bundled OpenStreetMap
  /// extract. Green reuses the grass fill, so the "Green space" legend row
  /// covers it, and a pitch adds the parking edge. No new colours.
  void _paintOsmGround(Canvas canvas, _MapGeometry geometry, Paint? grass) {
    final water = mapWaterPaints(scheme, zoom: zoom);
    final fill = water.fill;
    final edge = water.edge;
    if (fill != null && osm.water.isNotEmpty) {
      canvas.drawPath(geometry.osmWater, fill);
    }
    if (edge != null) {
      if (osm.water.isNotEmpty) {
        final outline = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = edge.strokeWidth / zoom
          ..color = edge.color;
        canvas.drawPath(geometry.osmWater, outline);
      }
      if (osm.waterway.isNotEmpty) {
        canvas.drawPath(
          geometry.osmWaterway,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / zoom
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = edge.color,
        );
      }
    }
    if (grass != null && (osm.park.isNotEmpty || osm.pitch.isNotEmpty)) {
      canvas.drawPath(geometry.osmGreen, grass);
    }
    final pitchEdge = mapPitchEdge(scheme, zoom: zoom);
    if (pitchEdge != null && osm.pitch.isNotEmpty) {
      pitchEdge.strokeWidth /= zoom;
      canvas.drawPath(geometry.osmPitchEdge, pitchEdge);
    }
  }

  /// Footprints only OpenStreetMap has, in the other-building family. They
  /// carry no name, no label and no tap target: RIT has nothing to say about
  /// them, so neither does the map.
  void _paintOsmBuildings(Canvas canvas, _MapGeometry geometry) {
    if (osm.building.isEmpty) return;
    final paints = mapFamilyPaints(MapFamily.otherBuilt, scheme, zoom: zoom);
    final fill = paints.fill;
    final edge = paints.edge;
    if (fill != null) canvas.drawPath(geometry.osmBuildings, fill);
    if (edge != null) {
      edge.strokeWidth /= zoom;
      canvas.drawPath(geometry.osmBuildings, edge);
    }
  }

  /// Doors, from 8x: a 6 pt dot with a 1 pt outline, constant on screen. Two
  /// draw calls however many doors there are.
  void _paintEntrances(Canvas canvas, _MapGeometry geometry) {
    final opacity = opacityAt(MapSchedule.entrances, zoom);
    if (opacity <= 0 || geometry.entrancePoints.isEmpty) return;
    final palette = MapPalette.of(scheme.brightness);
    Paint dot(double diameter, Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = diameter / zoom
      ..color = _faded(color, opacity);
    canvas.drawPoints(
      PointMode.points,
      geometry.entrancePoints,
      dot(_entranceDot + _entranceRing * 2, palette.entranceOutline),
    );
    canvas.drawPoints(
      PointMode.points,
      geometry.entrancePoints,
      dot(_entranceDot, palette.entrance),
    );
  }

  /// The ids of the buildings that can be labelled, for tests that check OSM
  /// footprints never join them.
  @visibleForTesting
  List<int> labelledBuildingIdsForTest(Size size) => [
    for (final b in _geometryFor(
      CampusMapProjection(features, size, boundsFeatures: boundsFeatures),
    ).buildings)
      b.feature.id,
  ];

  static _MapGeometry? _geometryCache;

  /// Only for tests that need a cold build.
  static void resetGeometryCacheForTest() => _geometryCache = null;

  /// How many times a geometry has been built, for tests that count rebuilds.
  @visibleForTesting
  static int geometryBuilds = 0;

  @visibleForTesting
  Object pinLayoutForTest(Size size) => _geometryFor(
    CampusMapProjection(features, size, boundsFeatures: boundsFeatures),
  ).pinBucketsAt(zoom);

  _MapGeometry _geometryFor(CampusMapProjection projection) {
    final cached = _geometryCache;
    // The projection is a pure function of its size and feature lists, so
    // equal inputs give an equal projection even when the object is new. The
    // screen builds a fresh list from the same features on every rebuild.
    if (cached != null &&
        cached.projection.size == projection.size &&
        _sameFeatures(cached.features, features) &&
        _sameFeatures(
          cached.projection._boundsFeatures,
          projection._boundsFeatures,
        ) &&
        identical(cached.paths, paths) &&
        identical(cached.osm, osm) &&
        cached.scheme == scheme) {
      return cached;
    }
    geometryBuilds++;
    return _geometryCache = _MapGeometry(
      projection,
      features,
      paths,
      scheme,
      osm,
    );
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
      ..color = MapPalette.of(scheme.brightness).chromeMuted.withValues(alpha: 0.75)
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
          fontFamily: AppTheme.uiFont,
          color: MapPalette.of(scheme.brightness).chromeMuted,
          fontSize: mapLabelMinSize / zoom,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2 / zoom,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(x, y - 5 / zoom - label.height));
  }

  /// Places building labels.
  ///
  /// At the default view only 30 of the 150 buildings used to carry one, even
  /// though 67 have an abbreviation, because a label that did not fit inside
  /// its own outline was simply dropped. Most campus buildings are small on
  /// screen, so most of them were anonymous.
  ///
  /// A label that does not fit inside now sits just below its building, which
  /// is what a paper map does, and every label is drawn over a halo so it
  /// survives crossing a footpath or another outline. Collision checking is
  /// unchanged: the biggest buildings claim their space first, and anything
  /// that would overlap an already-placed label is still dropped rather than
  /// stacked.
  static const double _glyphGap = 3;

  @visibleForTesting
  List<PlacedLabel> labelPlanForTest(Size size) {
    final geometry = _geometryFor(
      CampusMapProjection(features, size, boundsFeatures: boundsFeatures),
    );
    return _labelPlan(geometry, geometry.pinBucketsAt(zoom));
  }

  /// A street name set glyph by glyph along [curve], or null when the street
  /// has no gentle run, or the name is longer than it.
  LabelCandidate? _pathLabel(
    _MapGeometry geometry,
    String name,
    StraightRun? curve,
  ) {
    if (curve == null) return null;
    final inks = <_Ink>[];
    for (final char in name.characters) {
      final ink = geometry.ink(char, LabelClass.street);
      if (ink == null) return null;
      inks.add(ink);
    }
    final glyphs = layoutAlongRun(
      [for (final p in curve.points) p * zoom],
      [for (final ink in inks) ink.fill.width],
    );
    if (glyphs == null) return null;
    // the box round every glyph, for the collision planner
    Rect? box;
    for (final glyph in glyphs) {
      final ink = inks[glyph.index].fill;
      final rect = Rect.fromCenter(
        center: glyph.at,
        width: math.max(ink.width, ink.height),
        height: math.max(ink.width, ink.height),
      );
      box = box == null ? rect : box.expandToInclude(rect);
    }
    return LabelCandidate(
      key: ('street', name),
      cls: LabelClass.street,
      size: box!.size,
      positions: [box],
      text: name,
      payload: PathLabel(glyphs, inks),
    );
  }

  List<PlacedLabel> _labelPlan(_MapGeometry geometry, List<_PinBucket> pins) {
    const glyphGap = _glyphGap;
    final candidates = <LabelCandidate>[];
    // streets and doors, planned after everything else
    final osmCandidates = <LabelCandidate>[];

    for (final building in geometry.buildings) {
      final feature = building.feature;
      final id = feature.id;
      final bounds = building.bounds;
      // planned in screen points: the canvas coordinates times the zoom
      final screen = Rect.fromLTRB(
        bounds.left * zoom,
        bounds.top * zoom,
        bounds.right * zoom,
        bounds.bottom * zoom,
      );
      final icon = mapGlyph(building.family).on(platform);

      void add(
        LabelClass cls,
        String text, {
        double maxWidth = double.infinity,
        int maxLines = 1,
        bool outside = false,
      }) {
        final ink = geometry.ink(
          text,
          cls,
          maxWidth: maxWidth,
          maxLines: maxLines,
        );
        if (ink == null) return;
        final glyph = mapGlyphShown(cls, zoom)
            ? geometry.ink(String.fromCharCode(icon.codePoint), cls, icon: icon)
            : null;
        final size = Size(
          ink.fill.width + (glyph == null ? 0 : glyph.fill.width + glyphGap),
          math.max(ink.fill.height, glyph?.fill.height ?? 0),
        );
        candidates.add(
          LabelCandidate(
            key: id,
            cls: cls,
            size: size,
            positions: buildingPositions(screen, size, outside: outside),
            // a building shows one name, the best that wins a place
            group: id,
            weight: screen.width * screen.height,
            text: text,
            glyph: glyph != null,
            payload: (ink, glyph),
          ),
        );
      }

      final abbreviation = feature.building;
      final hasAbbreviation = abbreviation != null && abbreviation.isNotEmpty;
      if (id == selectedId) {
        add(
          LabelClass.selected,
          feature.name.isNotEmpty ? feature.name : abbreviation ?? '',
          maxWidth: 150,
          maxLines: 2,
          outside: true,
        );
      }
      if (zoom >= mapGlyphMinZoom && feature.name.isNotEmpty) {
        add(
          LabelClass.fullName,
          feature.name,
          maxWidth: 96,
          maxLines: 2,
          outside: zoom >= mapFullNameOutsideZoom,
        );
      }
      if (hasAbbreviation) {
        add(
          LabelClass.abbreviation,
          abbreviation,
          outside: zoom >= mapGlyphMinZoom || geometry.landmarkIds.contains(id),
        );
      }
    }

    // One label per street, upright, on its longest straight run. It is
    // dropped when the run is shorter than the name, and it loses every
    // collision to a building, a pin or a selected label.
    if (zoom >= mapStreetMinZoom) {
      for (final street in geometry.streets) {
        final ink = geometry.ink(street.name, LabelClass.street);
        if (ink == null) continue;
        final w = ink.fill.width;
        final h = ink.fill.height;
        // Set along the street where it bends gently. Anything harder, or too
        // short for the name, falls back to the upright label below.
        final onPath = _pathLabel(geometry, street.name, street.curve);
        if (onPath != null) {
          osmCandidates.add(onPath);
          continue;
        }
        final run = street.run;
        final room = run.length * zoom;
        if (room < w) continue;
        Rect around(double fraction) => Rect.fromCenter(
          center: pointAlong(run.points, fraction) * zoom,
          width: w,
          height: h,
        );
        osmCandidates.add(
          LabelCandidate(
            key: ('street', street.name),
            cls: LabelClass.street,
            size: Size(w, h),
            positions: [
              around(.5),
              // slid along the run, while the name still fits on it
              for (final f in const [.35, .65])
                if (f * room >= w / 2 && (1 - f) * room >= w / 2) around(f),
            ],
            text: street.name,
            payload: (ink, null),
          ),
        );
      }
    }

    // Only a named door is labelled, and only at the closest zoom.
    if (zoom >= mapZoomStops.last) {
      for (final door in geometry.entrances) {
        final name = door.name;
        if (name == null) continue;
        final ink = geometry.ink(
          name,
          LabelClass.entrance,
          maxWidth: 130,
          maxLines: 3,
        );
        if (ink == null) continue;
        final w = ink.fill.width;
        final h = ink.fill.height;
        final at = door.at * zoom;
        final gap = _entranceDot / 2 + _entranceRing + 3;
        osmCandidates.add(
          LabelCandidate(
            key: ('door', door.at),
            cls: LabelClass.entrance,
            size: Size(w, h),
            positions: [
              Rect.fromLTWH(at.dx + gap, at.dy - h / 2, w, h),
              Rect.fromLTWH(at.dx - gap - w, at.dy - h / 2, w, h),
              Rect.fromLTWH(at.dx - w / 2, at.dy - gap - h, w, h),
              Rect.fromLTWH(at.dx - w / 2, at.dy + gap, w, h),
            ],
            text: name,
            payload: (ink, null),
          ),
        );
      }
    }

    final obstacles = <Rect>[];
    if (!geometry.categoryOverview) {
      for (final pin in pins) {
        final selected = pin.items.any((item) => item.feature.id == selectedId);
        final radius = _pinRadius(pin, selected);
        final at = pin.center * zoom;
        obstacles.add(Rect.fromCircle(center: at, radius: radius));
        if (selected && pin.items.length == 1) {
          final name = pin.items.single.feature.name;
          final ink = geometry.ink(
            name,
            LabelClass.activePin,
            maxWidth: 140,
            maxLines: 2,
          );
          if (ink == null) continue;
          final w = ink.fill.width;
          final h = ink.fill.height;
          final gap = radius + 3;
          candidates.add(
            LabelCandidate(
              key: pin.items.single.feature.id,
              cls: LabelClass.activePin,
              size: Size(w, h),
              positions: [
                Rect.fromLTWH(at.dx + gap, at.dy - h / 2, w, h),
                Rect.fromLTWH(at.dx - gap - w, at.dy - h / 2, w, h),
                Rect.fromLTWH(at.dx - w / 2, at.dy - gap - h, w, h),
                Rect.fromLTWH(at.dx - w / 2, at.dy + gap, w, h),
              ],
              text: name,
              payload: (ink, null),
            ),
          );
        }
      }
    }

    final placed = planLabels(candidates, obstacles: obstacles);
    if (osmCandidates.isEmpty) return placed;
    // Planned apart, against what is already down, so a street or a door can
    // never change which building label wins a tie.
    return [
      ...placed,
      ...planLabels(
        osmCandidates,
        obstacles: [...obstacles, for (final p in placed) p.rect],
      ),
    ];
  }

  void _paintLabels(
    Canvas canvas,
    _MapGeometry geometry,
    List<_PinBucket> pins,
  ) {
    const glyphGap = _glyphGap;
    final placed = _labelPlan(geometry, pins);
    canvas.save();
    // Constant on screen, so zooming in shrinks a label against its building
    // and lets more of them fit.
    canvas.scale(1 / zoom);
    for (final label in placed) {
      final payload = label.candidate.payload;
      if (payload is PathLabel) {
        // each glyph is turned to the street at its own place along it
        for (final glyph in payload.glyphs) {
          final ink = payload.inks[glyph.index];
          canvas.save();
          canvas.translate(glyph.at.dx, glyph.at.dy);
          canvas.rotate(glyph.angle);
          final at = Offset(-ink.fill.width / 2, -ink.fill.height / 2);
          ink.halo.paint(canvas, at);
          ink.fill.paint(canvas, at);
          canvas.restore();
        }
        continue;
      }
      final (ink, glyph) = payload! as (_Ink, _Ink?);
      var x = label.rect.left;
      if (glyph != null) {
        final at = Offset(x, label.rect.center.dy - glyph.fill.height / 2);
        glyph.halo.paint(canvas, at);
        glyph.fill.paint(canvas, at);
        x += glyph.fill.width + glyphGap;
      }
      final at = Offset(x, label.rect.center.dy - ink.fill.height / 2);
      ink.halo.paint(canvas, at);
      ink.fill.paint(canvas, at);
    }
    canvas.restore();
  }

  /// Screen radius of a pin: 22 pt single, 30 selected or counted, 34 from ten.
  double _pinRadius(_PinBucket pin, bool selected) {
    final counted =
        pin.items.length > 1 ||
        pin.items.first.feature.kind.startsWith('_event:');
    final total = pin.items.fold<int>(0, (sum, item) {
      final kind = item.feature.kind;
      return sum +
          (kind.startsWith('_event:') ? int.tryParse(kind.substring(7)) ?? 1 : 1);
    });
    if (counted && total >= 10) return 17.0;
    return selected || counted ? 15.0 : 11.0;
  }

  /// The pin count, measured at its screen size of 11 pt.
  TextPainter _countPainter(String count, Color color) => TextPainter(
    text: TextSpan(
      text: count,
      style: TextStyle(
        fontFamily: AppTheme.uiFont,
        color: color,
        fontSize: mapCountSize,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintCount(
    Canvas canvas,
    TextPainter painter,
    Offset center,
    double zoom,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1 / zoom);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
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
      oldDelegate.platform != platform ||
      oldDelegate.zoom != zoom ||
      oldDelegate.paths != paths ||
      oldDelegate.osm != osm;

  @override
  bool shouldRebuildSemantics(CampusMapPainter oldDelegate) =>
      oldDelegate.features != features ||
      oldDelegate.boundsFeatures != boundsFeatures ||
      oldDelegate.selectedId != selectedId ||
      (oldDelegate.zoom * 4).round() != (zoom * 4).round();
}

/// Names the three outline families.
///
/// Without it the map asks you to infer that a hollow shape is a car park and
/// an olive one is grass. The swatches are painted with `mapFamilyPaints`, the
/// same function the map uses, so the legend cannot describe colours the map
/// is not drawing.
/// The projected geometry, built once and reused across frames.
///
/// Every frame used to re-project roughly 9550 coordinates, allocate a fresh
/// Path for each of the 191 outlines and 1824 ways, and then issue one draw
/// call per way. None of that changes while you are looking at the map, and
/// 1824 separate strokes give Skia nothing to batch.
///
/// Now each layer is a single Path with many subpaths, so the whole walking
/// network is two draw calls rather than 1824, and the work happens once per
/// projection rather than once per frame.
typedef _Pin = ({CampusMapFeature feature, Offset at});
typedef _PinBucket = ({List<_Pin> items, Offset center});
typedef _Building = ({
  CampusMapFeature feature,
  MapFamily family,
  Rect bounds,
});
typedef _Ink = ({TextPainter fill, TextPainter halo});

class _MapGeometry {
  _MapGeometry(
    this.projection,
    this.features,
    this.paths,
    this.scheme, [
    this.osm = const OsmFeatures.empty(),
  ]) {
    List<List<Offset>> projected(List<List<GeoCoordinate>> rings) => [
      for (final ring in rings) [for (final c in ring) projection.project(c)],
    ];
    osmWater = ringsPath(projected(osm.water));
    osmWaterway = linesPath(projected(osm.waterway));
    // RIT's own outlines, kept so OpenStreetMap can be checked against them
    final ritBuilt = <List<Offset>>[];
    final ritOpen = <List<Offset>>[];
    for (final feature in features) {
      if (feature.geometryType == 'Point') continue;
      final family = mapFamily(feature);
      final layer = areas.putIfAbsent(family, Path.new);
      Rect? largest;
      for (final ring in feature.coordinates) {
        if (ring.length < 3) continue;
        final points = [for (final c in ring) projection.project(c)];
        if (family.isBuilt) ritBuilt.add(points);
        if (family == MapFamily.open) ritOpen.add(points);
        final outline = Path()..addPolygon(points, true);
        layer.addPath(outline, Offset.zero);
        final bounds = outline.getBounds();
        if (largest == null ||
            bounds.width * bounds.height > largest.width * largest.height) {
          largest = bounds;
        }
      }
      // Only buildings are labelled. A lot number on every parking apron is
      // the noise that made the campus hard to read in the first place.
      if (largest != null && family.isBuilt) {
        buildings.add((feature: feature, family: family, bounds: largest));
      }
    }
    // RIT stays authoritative. An OpenStreetMap park whose centre is already
    // inside one of RIT's green shapes is dropped, a pitch there keeps only
    // its edge, and a footprint is kept only where RIT has none.
    bool inRitOpen(List<Offset> ring) =>
        ritOpen.any((open) => pointInRing(ringCentre(ring), open));
    final pitches = projected(osm.pitch);
    osmGreen = ringsPath([
      for (final ring in projected(osm.park))
        if (!inRitOpen(ring)) ring,
      for (final ring in pitches)
        if (!inRitOpen(ring)) ring,
    ]);
    osmPitchEdge = ringsPath(pitches);
    osmBuildings = ringsPath(outsideRings(projected(osm.building), ritBuilt));
    for (final street in osm.street) {
      final run = longestStraightRun(projected(street.lines));
      if (run == null) continue;
      streets.add((
        name: street.name,
        run: run,
        curve: longestGentleRun(projected(street.lines)),
      ));
    }
    // the few buildings that keep a name at campus scale, by footprint
    final named = [
      for (final b in buildings)
        if ((b.feature.building ?? '').isNotEmpty) b,
    ]..sort(
        (a, b) => (b.bounds.width * b.bounds.height).compareTo(
          a.bounds.width * a.bounds.height,
        ),
      );
    landmarkIds = {for (final b in named.take(6)) b.feature.id};
    foot = _network(paths.foot);
    road = _network(paths.road);

    pointKinds = {
      for (final feature in features)
        if (feature.geometryType == 'Point') feature.kind,
    };
    categoryOverview =
        pointKinds.length > 1 &&
        pointKinds.every((kind) => !kind.startsWith('_event:'));
    // A door within a few metres of an RIT accessible entrance pin is the
    // same door, and the pin already marks it. In the overview no pin is drawn,
    // so the door stays.
    final ritDoors = [
      if (!categoryOverview)
        for (final feature in features)
          if (feature.geometryType == 'Point' &&
              feature.kind == 'entrance_accessible' &&
              feature.anchor != null)
            feature.anchor!,
    ];
    for (final door in osm.entrance) {
      if (ritDoors.any((d) => metresApart(d, door.at) < _sameDoorMetres)) {
        continue;
      }
      entrances.add((at: projection.project(door.at), name: door.name));
    }
    entrancePoints = [for (final door in entrances) door.at];
    for (final feature in features) {
      if (feature.geometryType != 'Point') continue;
      final anchor = feature.anchor;
      if (anchor == null) continue;
      pointLocations.add((feature: feature, at: projection.project(anchor)));
    }
  }

  List<_PinBucket> pinBucketsAt(double zoom) {
    final clusterCell = 46.0 / zoom;
    final visible = projection.mapRect.inflate(12 / zoom);
    final keys = <Object?>[];
    for (final point in pointLocations) {
      final center = point.at;
      if (!visible.contains(center)) {
        keys.add(null);
        continue;
      }
      // The overview gets one meaningful marker per category. Once a category
      // is selected, nearby individual places use spatial clusters. Event
      // groups keep spatial clustering as well because each group has a
      // synthetic kind of its own.
      final Object key = categoryOverview
          ? point.feature.kind
          : (
              (center.dx / clusterCell).floor(),
              (center.dy / clusterCell).floor(),
            );
      keys.add(key);
    }
    final oldKeys = _pinKeys;
    if (oldKeys != null && oldKeys.length == keys.length) {
      var same = true;
      for (var i = 0; i < keys.length; i++) {
        if (oldKeys[i] != keys[i]) {
          same = false;
          break;
        }
      }
      if (same) return _pinBuckets!;
    }

    final groups = <Object, List<_Pin>>{};
    final sums = <Object, Offset>{};
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      if (key == null) continue;
      final point = pointLocations[i];
      groups.putIfAbsent(key, () => []).add(point);
      sums[key] = (sums[key] ?? Offset.zero) + point.at;
    }
    _pinKeys = keys;
    return _pinBuckets = [
      for (final entry in groups.entries)
        (
          items: entry.value,
          center: sums[entry.key]! / entry.value.length.toDouble(),
        ),
    ];
  }

  final CampusMapProjection projection;
  final List<CampusMapFeature> features;
  final CampusPaths paths;
  final ColorScheme scheme;
  final OsmFeatures osm;

  /// One path per OpenStreetMap layer, every ring wound the same way so
  /// overlaps fill once. Green and pitches share a path so they never blend
  /// twice.
  late final Path osmWater;
  late final Path osmWaterway;
  late final Path osmGreen;
  late final Path osmPitchEdge;

  /// OpenStreetMap footprints RIT does not draw. Unlabeled and not selectable.
  late final Path osmBuildings;

  /// OpenStreetMap doors RIT has no pin for, projected. Named ones get a label
  /// at the closest zoom.
  final List<({Offset at, String? name})> entrances = [];
  late final List<Offset> entrancePoints;

  /// Each named street with its longest straight run, where its label goes.
  final List<({String name, StraightRun run, StraightRun? curve})> streets =
      [];

  final Map<MapFamily, Path> areas = {};
  final List<_Building> buildings = [];
  late final Set<int> landmarkIds;
  final Map<String, _Ink?> _ink = {};

  /// A label's text and its halo, laid out once at its screen size. Null when
  /// the text will not fit [maxLines] lines in [maxWidth], so a long name is
  /// dropped rather than clipped.
  _Ink? ink(
    String text,
    LabelClass cls, {
    double maxWidth = double.infinity,
    int maxLines = 1,
    IconData? icon,
  }) => _ink.putIfAbsent('${cls.name}|$maxWidth|$maxLines|$icon|$text', () {
    final palette = MapPalette.of(scheme.brightness);
    TextPainter measure(TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final base = icon == null
        ? TextStyle(
            fontFamily: AppTheme.uiFont,
            fontSize: cls.size,
            fontWeight: cls.weight,
            height: 1.15,
          )
        : TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: cls.size,
          );
    final fill = measure(base.copyWith(color: palette.labelInk));
    if (fill.didExceedMaxLines) return null;
    return (
      fill: fill,
      // drawn first, so a label survives crossing a footpath or an edge
      halo: measure(
        base.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cls.halo * 2
            ..strokeJoin = StrokeJoin.round
            ..color = palette.labelHalo,
        ),
      ),
    );
  });
  final List<_Pin> pointLocations = [];
  List<Object?>? _pinKeys;
  List<_PinBucket>? _pinBuckets;
  late final Set<String> pointKinds;
  late final bool categoryOverview;
  late final Path foot;
  late final Path road;

  Path _network(List<List<GeoCoordinate>> ways) {
    final path = Path();
    for (final way in ways) {
      if (way.length < 2) continue;
      path.addPolygon([for (final c in way) projection.project(c)], false);
    }
    return path;
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.scheme});

  final ColorScheme scheme;

  MapPalette get map => MapPalette.of(scheme.brightness);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: map.chrome.withValues(alpha: 0.9),
        // a pill on one row, rounded when it wraps
        borderRadius: Shapes.inner,
        border: Border.all(color: map.chromeEdge.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Wrap(
          spacing: 14,
          // The rows are already tall at large text, and a legend that runs
          // off the map hides its own credit.
          runSpacing: MediaQuery.textScalerOf(context).scale(mapLabelMinSize) >
                  mapLabelMinSize * 1.5
              ? 2
              : 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _entry(MapFamily.academic, 'Academic'),
            _entry(MapFamily.residential, 'Residential'),
            _entry(MapFamily.athletic, 'Athletic'),
            _entry(MapFamily.dining, 'Dining'),
            _entry(MapFamily.otherBuilt, 'Other building'),
            _entry(MapFamily.parking, 'Parking'),
            _entry(MapFamily.open, 'Green space'),
            _entry(null, 'Water'),
            _lineEntry('Road', path: false),
            _lineEntry('Walk path', path: true),
            Text(
              '(c) OpenStreetMap contributors, ODbL',
              style: TextStyle(
                fontSize: mapLabelMinSize,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: map.chromeMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A null family is the water swatch.
  Widget _entry(MapFamily? family, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CustomPaint(
        size: const Size(15, 10),
        painter: _LegendSwatch(family: family, scheme: scheme),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            fontSize: mapLabelMinSize,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: map.chromeMuted,
          ),
        ),
      ),
    ],
  );

  Widget _lineEntry(String label, {required bool path}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 17,
        child: Divider(
          height: 2,
          thickness: path ? 2 : 4,
          color: path
              ? MapPalette.of(scheme.brightness).footpath
              : MapPalette.of(scheme.brightness).roadCore,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            fontSize: mapLabelMinSize,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: map.chromeMuted,
          ),
        ),
      ),
    ],
  );
}

class _LegendSwatch extends CustomPainter {
  const _LegendSwatch({required this.family, required this.scheme});

  /// Null paints the water swatch.
  final MapFamily? family;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final family = this.family;
    final paints = family == null
        ? mapWaterPaints(scheme)
        : mapFamilyPaints(family, scheme);
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
