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
  Size _viewportSize = Size.zero;

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
    final matrix = _transform.value;
    final current = matrix.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 5.0);
    final applied = target / current;
    if (applied == 1) return;
    final focus = _viewportSize.isEmpty
        ? Offset.zero
        : _viewportSize.center(Offset.zero);
    final translatedX = focus.dx - applied * (focus.dx - matrix.entry(0, 3));
    final translatedY = focus.dy - applied * (focus.dy - matrix.entry(1, 3));
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, target)
      ..setEntry(1, 1, target)
      ..setEntry(0, 3, translatedX)
      ..setEntry(1, 3, translatedY);
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
    List<CampusMapFeature> backdrop,
  ) async {
    final searchable = [
      for (final feature in all)
        if ((feature.geometryType == 'Point' &&
                !feature.kind.startsWith('_')) ||
            (feature.kind == '_campus' && feature.building != null))
          feature,
    ];
    final feature = await showSearch<CampusMapFeature?>(
      context: context,
      delegate: _MapSearchDelegate(searchable),
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
      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, _viewportSize.width / 2 - point.dx * scale)
        ..setEntry(1, 3, _viewportSize.height / 2 - point.dy * scale);
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
    final selectedBuilding = backdrop
        .where((feature) => feature.id == _selectedId)
        .firstOrNull;
    final selectedEvent = eventMap.groups
        .where((group) => group.id == _selectedId)
        .firstOrNull;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchPlaces(all, backdrop),
      },
      child: Column(
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
                color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                                              zoom: matrix.getMaxScaleOnAxis(),
                                              paths: _paths,
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
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _MapLegend(
                            scheme: Theme.of(context).colorScheme,
                          ),
                        ),
                        const Positioned(
                          right: 12,
                          top: 12,
                          child: _NorthIndicator(),
                        ),
                        Positioned(
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
          SizedBox(
            height:
                selected == null &&
                    selectedBuilding == null &&
                    selectedEvent == null
                ? 92
                : 146,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Map is oriented north up',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'North up',
          child: Material(
            color: scheme.surface.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            child: SizedBox.square(
              dimension: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.navigation_rounded,
                    size: 25,
                    color: scheme.primary,
                  ),
                  Positioned(
                    bottom: 3,
                    child: Text(
                      'N',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (zoom < 1.15) ...[
          Material(
            color: scheme.surface.withValues(alpha: 0.92),
            shape: Shapes.pill,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 7),
                  const Text('Zoom in for walking paths'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Material(
          color: scheme.surface.withValues(alpha: 0.92),
          borderRadius: Shapes.inner,
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Zoom out',
                onPressed: zoom > 1.01 ? onZoomOut : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${zoom.toStringAsFixed(1).replaceFirst('.0', '')}×',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: zoom < 4.99 ? onZoomIn : null,
                icon: const Icon(Icons.add_rounded),
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

class _MapSearchDelegate extends SearchDelegate<CampusMapFeature?> {
  _MapSearchDelegate(this.features)
    : super(searchFieldLabel: 'Building, room, or campus place');

  final List<CampusMapFeature> features;

  List<CampusMapFeature> get _matches {
    final needle = query.trim().toLowerCase();
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
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear search',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back to map',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final matches = _matches;
    if (matches.isEmpty) {
      return const Center(child: Text('No campus places match that search.'));
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final feature = matches[index];
        final location = feature.where;
        final isBuilding = feature.kind == '_campus';
        final palette = mapPinPalette(
          feature.kind,
          Theme.of(context).colorScheme,
        );
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: palette.$1,
            foregroundColor: palette.$2,
            child: Icon(mapPlaceIcon(feature.kind)),
          ),
          title: Text(feature.name),
          subtitle: Text(
            isBuilding
                ? '${feature.kindName} · ${feature.building}'
                : location.isEmpty
                ? feature.kindName
                : '${feature.kindName} · $location',
          ),
          onTap: () => close(context, feature),
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
        ? Icons.apps_rounded
        : mapPlaceIcon(selectedKind!);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Search campus places (Ctrl+F)',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        const SizedBox(width: 8),
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
              for (final entry
                  in kinds.entries.toList()
                    ..sort((a, b) => a.value.compareTo(b.value)))
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
      scrollDirection: Axis.horizontal,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final scheme = Theme.of(context).colorScheme;
        final palette = mapPinPalette(entry.key, scheme);
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
                      child: Icon(
                        mapPlaceIcon(entry.key),
                        size: 20,
                        color: palette.$2,
                      ),
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
    this.iconSize = 17,
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
IconData mapPlaceIcon(String kind) => switch (kind) {
  '_campus' => Icons.location_city_rounded,
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
  'time_clock' => Icons.punch_clock_rounded,
  'printer' => Icons.print_rounded,
  'study_area' => Icons.menu_book_rounded,
  'computer_lab' => Icons.computer_rounded,
  'connection_hub' => Icons.hub_rounded,
  'lactation' => Icons.child_care_rounded,
  'vending' => Icons.local_drink_rounded,
  'convenience' => Icons.storefront_rounded,
  'food_share' => Icons.volunteer_activism_rounded,
  'bottle_return' => Icons.recycling_rounded,
  'support_services' => Icons.support_agent_rounded,
  'higi_kiosk' => Icons.monitor_heart_rounded,
  'gym' => Icons.fitness_center_rounded,
  _ when kind.startsWith('_event:') => Icons.event_rounded,
  _ => Icons.place_rounded,
};

(Color, Color) mapPinPalette(String kind, ColorScheme scheme) => switch (kind) {
  'water' ||
  'ev_charge' ||
  'bus_stop' ||
  'bike_rack' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
  'aed' || 'blue_light' || 'restroom_accessible' || 'entrance_accessible' => (
    scheme.tertiaryContainer,
    scheme.onTertiaryContainer,
  ),
  _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
};

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
  return MapFamily.otherBuilt;
}

/// The category colours, validated rather than eyeballed.
///
/// docs/notes.md 4 requires the dataviz validator to sign off any palette. Both of
/// these pass all six checks against their own surface:
///
///   light  #0069a8 #6a4c93 #b4531f #4f7a28
///          CVD worst adjacent dE 18.8 deutan, normal-vision worst 21.5
///   dark   #3d8dc4 #8a6cc0 #cc6a38 #669440
///          CVD worst adjacent dE 19.7 protan, normal-vision worst 21.7
///
/// Residential is the purple rather than the orange because orange is the
/// app's primary, and 106 buildings in something close to it would read as
/// 106 selected buildings. Green is spent on the two "other" buildings rather
/// than on athletics, to keep it away from the olive of the green spaces.
///
/// Colour is never the only carrier: every one of these is named in the map's
/// legend, and buildings carry their abbreviation on the map itself.
Color _categoryColor(MapFamily family, Brightness brightness) {
  final light = brightness == Brightness.light;
  return switch (family) {
    MapFamily.academic =>
      light ? const Color(0xFF0069A8) : const Color(0xFF3D8DC4),
    MapFamily.residential =>
      light ? const Color(0xFF6A4C93) : const Color(0xFF8A6CC0),
    MapFamily.athletic =>
      light ? const Color(0xFFB4531F) : const Color(0xFFCC6A38),
    _ => light ? const Color(0xFF4F7A28) : const Color(0xFF669440),
  };
}

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
    default:
      final category = _categoryColor(family, scheme.brightness);
      return (
        // A restrained tint makes zones readable as areas, rather than asking
        // the reader to trace dozens of differently coloured outlines.
        fill: Paint()..color = category.withValues(alpha: 0.16),
        edge: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = category,
      );
  }
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
        if (family == MapFamily.parking && zoom < 1.15) {
          edge.color = edge.color.withValues(alpha: 0.28);
        }
        canvas.drawPath(path, edge);
      }
    }

    // Ground first, then the paths crossing it, then what you walk into.
    drawFamily(MapFamily.open);
    drawFamily(MapFamily.parking);
    _paintPaths(canvas, geometry, mapRect);
    for (final family in MapFamily.values.where((family) => family.isBuilt)) {
      drawFamily(family);
    }

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
      canvas.drawPath(
        outline,
        Paint()..color = scheme.primary.withValues(alpha: 0.3),
      );
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 / zoom
          ..color = scheme.primary,
      );
    }

    _paintBuildingLabels(canvas, geometry.labels, scheme);
    _paintScaleBar(canvas, projection, mapRect, scheme);

    final buckets = geometry.pins;

    // "All places" is a category chooser, not a heat map. Almost every kind
    // is concentrated in the academic core, so showing all twelve at once
    // creates a misleading knot. The icon cards below provide the overview;
    // spatial markers appear after the reader chooses a category.
    for (final entry
        in geometry.categoryOverview
            ? const <
                MapEntry<Object, List<({CampusMapFeature feature, Offset at})>>
              >[]
            : buckets.entries) {
      final bucket = entry.value;
      final center = geometry.pinCenters[entry.key]!;
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
          ? 18.0 / zoom
          : geometry.categoryOverview
          ? 20.0 / zoom
          : clustered
          ? 16.0 / zoom
          : 13.0 / zoom;
      final isEvent = bucket.first.feature.kind.startsWith('_event:');
      final palette = mapPinPalette(bucket.first.feature.kind, scheme);
      final foreground = selected || isEvent ? scheme.onPrimary : palette.$2;
      canvas.drawPath(
        _scallop(center, radius),
        Paint()..color = selected || isEvent ? scheme.primary : palette.$1,
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
          center - Offset(5.5 / zoom, 0),
          foreground,
          11 / zoom,
        );
        _paintMapCount(
          canvas,
          '$eventCount',
          center + Offset(7 / zoom, 0),
          foreground,
          scale: 1 / zoom,
        );
      } else {
        _paintMapIcon(
          canvas,
          mapPlaceIcon(bucket.single.feature.kind),
          center,
          foreground,
          15 / zoom,
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
  void _paintPaths(Canvas canvas, _MapGeometry geometry, Rect mapRect) {
    if (paths.isEmpty) return;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(mapRect.inflate(18), const Radius.circular(32)),
    );
    // Roads get a casing and centre stroke, like an actual campus map. At the
    // overview scale the dense footway graph is withheld; it fades into the
    // job only when zooming makes those choices useful.
    canvas.drawPath(
      geometry.road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2 / zoom
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = scheme.surfaceContainerHighest.withValues(
          alpha: zoom < 1.15 ? 0.68 : 0.9,
        ),
    );
    canvas.drawPath(
      geometry.road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35 / zoom
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = scheme.onSurfaceVariant.withValues(
          alpha: zoom < 1.15 ? 0.32 : 0.52,
        ),
    );
    if (zoom >= 1.15) {
      canvas.drawPath(
        geometry.foot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15 / zoom
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = scheme.primary.withValues(alpha: 0.72),
      );
    }
    canvas.restore();
  }

  static _MapGeometry? _geometryCache;

  /// Only for tests that need a cold build.
  static void resetGeometryCacheForTest() => _geometryCache = null;

  _MapGeometry _geometryFor(CampusMapProjection projection) {
    final cached = _geometryCache;
    if (cached != null &&
        identical(cached.projection, projection) &&
        identical(cached.features, features) &&
        identical(cached.paths, paths) &&
        cached.scheme == scheme) {
      return cached;
    }
    return _geometryCache = _MapGeometry(projection, features, paths, scheme);
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
  void _paintBuildingLabels(
    Canvas canvas,
    List<({TextPainter halo, TextPainter painter, Rect bounds, double area})>
    candidates,
    ColorScheme scheme,
  ) {
    final ordered = [...candidates]..sort((a, b) => b.area.compareTo(a.area));
    final taken = <Rect>[];
    final maxLabels = zoom < 1.15
        ? 14
        : zoom < 1.8
        ? 30
        : 64;

    for (final candidate in ordered) {
      final painter = candidate.painter;
      // Measured once at the base size. Dividing by the zoom gives what it
      // covers on the canvas, without measuring it again.
      final width = painter.width / zoom;
      final height = painter.height / zoom;
      final bounds = candidate.bounds;

      // Inside if it fits with a little room, or it reads as a label for
      // whatever is next door. Otherwise directly beneath.
      final insideFits =
          width + 6 / zoom <= bounds.width &&
          height + 4 / zoom <= bounds.height;
      // At campus overview, label only genuine landmarks. Smaller buildings
      // become named progressively as zoom creates room for them.
      if (zoom < 1.15 && !insideFits) continue;
      final center = insideFits
          ? bounds.center
          : Offset(bounds.center.dx, bounds.bottom + height / 2 + 3 / zoom);

      final rect = Rect.fromCenter(
        center: center,
        width: width + 4 / zoom,
        height: height + 2 / zoom,
      );
      if (taken.any(rect.overlaps)) continue;

      taken.add(rect);
      if (taken.length > maxLabels) break;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      // Constant on screen, so zooming in shrinks the label against the
      // building and lets more of them fit.
      canvas.scale(1 / zoom);
      final at = Offset(-painter.width / 2, -painter.height / 2);
      candidate.halo.paint(canvas, at);
      painter.paint(canvas, at);
      canvas.restore();
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

  void _paintMapCount(
    Canvas canvas,
    String count,
    Offset center,
    Color color, {
    double scale = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: count,
        style: TextStyle(
          color: color,
          fontSize: 9 * scale,
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
class _MapGeometry {
  _MapGeometry(this.projection, this.features, this.paths, this.scheme) {
    for (final feature in features) {
      if (feature.geometryType == 'Point') continue;
      final family = mapFamily(feature);
      final layer = areas.putIfAbsent(family, Path.new);
      for (final ring in feature.coordinates) {
        if (ring.length < 3) continue;
        final outline = Path()
          ..addPolygon([for (final c in ring) projection.project(c)], true);
        layer.addPath(outline, Offset.zero);

        // Only buildings are labelled. A lot number on every parking apron is
        // the noise that made the campus hard to read in the first place.
        if (!family.isBuilt) continue;
        final abbreviation = feature.building;
        if (abbreviation == null || abbreviation.isEmpty) continue;
        final bounds = outline.getBounds();
        // Laid out once, at a base size. The zoom is applied as a transform
        // when it is drawn, so a zoom frame never measures text again.
        TextPainter measure(TextStyle style) => TextPainter(
          text: TextSpan(text: abbreviation, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        const base = TextStyle(
          fontSize: labelBaseSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        );
        labels.add((
          // Drawn behind the text so a label stays readable where it crosses
          // a footpath or the edge of its own building.
          halo: measure(
            base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4
                ..strokeJoin = StrokeJoin.round
                ..color = scheme.surface,
            ),
          ),
          painter: measure(base.copyWith(color: scheme.onSurfaceVariant)),
          bounds: bounds,
          area: bounds.width * bounds.height,
        ));
      }
    }
    foot = _network(paths.foot);
    road = _network(paths.road);

    pointKinds = {
      for (final feature in features)
        if (feature.geometryType == 'Point') feature.kind,
    };
    categoryOverview =
        pointKinds.length > 1 &&
        pointKinds.every((kind) => !kind.startsWith('_event:'));
    clusterCell = 46.0;
    final visible = projection.mapRect.inflate(12);
    for (final feature in features) {
      if (feature.geometryType != 'Point') continue;
      final anchor = feature.anchor;
      if (anchor == null) continue;
      final center = projection.project(anchor);
      if (!visible.contains(center)) continue;
      // The overview gets one meaningful marker per category. Once a category
      // is selected, nearby individual places use spatial clusters. Event
      // groups keep spatial clustering as well because each group has a
      // synthetic kind of its own.
      final Object key = categoryOverview
          ? feature.kind
          : (
              (center.dx / clusterCell).floor(),
              (center.dy / clusterCell).floor(),
            );
      pins.putIfAbsent(key, () => []).add((feature: feature, at: center));
    }
    _layoutPins();
  }

  /// Labels are measured at this size and scaled when drawn.
  static const double labelBaseSize = 9;

  final CampusMapProjection projection;
  final List<CampusMapFeature> features;
  final CampusPaths paths;
  final ColorScheme scheme;

  final Map<MapFamily, Path> areas = {};
  final List<
    ({TextPainter halo, TextPainter painter, Rect bounds, double area})
  >
  labels = [];
  final Map<Object, List<({CampusMapFeature feature, Offset at})>> pins = {};
  final Map<Object, Offset> pinCenters = {};
  late final Set<String> pointKinds;
  late final bool categoryOverview;
  late final double clusterCell;
  late final Path foot;
  late final Path road;

  void _layoutPins() {
    for (final entry in pins.entries) {
      final bucket = entry.value;
      final center = Offset(
        bucket.map((item) => item.at.dx).reduce((a, b) => a + b) /
            bucket.length,
        bucket.map((item) => item.at.dy).reduce((a, b) => a + b) /
            bucket.length,
      );
      pinCenters[entry.key] = center;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Wrap(
          spacing: 14,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _entry(MapFamily.academic, 'Academic'),
            _entry(MapFamily.residential, 'Residential'),
            _entry(MapFamily.athletic, 'Athletic'),
            _entry(MapFamily.otherBuilt, 'Other building'),
            _entry(MapFamily.parking, 'Parking'),
            _entry(MapFamily.open, 'Green space'),
            _lineEntry('Road', path: false),
            _lineEntry('Walk path', path: true),
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

  Widget _lineEntry(String label, {required bool path}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 17,
        child: Divider(
          height: 2,
          thickness: path ? 2 : 4,
          color: path
              ? scheme.primary.withValues(alpha: 0.8)
              : scheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
      const SizedBox(width: 6),
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
