/// The campus map, as its own destination.
///
/// It was a section inside the Campus tab, which buried it: the map is the
/// thing you open deliberately when you want to find somewhere, not something
/// you scroll past on the way to post office hours.
///
/// The map itself is `widgets/campus_map.dart`, painted from cached GeoJSON
/// with no tiles and no API key, so it works with no network like everything
/// else here.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../services/subscriptions.dart';
import '../widgets/campus_map.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.api, this.events});

  final ApiClient api;

  /// Passed through so the map can place events at the buildings that host
  /// them. Owned by the shell, since the Events tab needs the same data.
  final Result<Collection<CampusEvent>>? events;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Result<Collection<CampusMapFeature>> _map = const Result(
    value: null,
    state: DataState.priming,
  );

  /// Held so it can be cancelled. A dangling subscription delivers into a
  /// screen that has gone, and an older result can overwrite a newer one.
  final _subscriptions = Subscriptions();

  @override
  void initState() {
    super.initState();
    _subscriptions.add(widget.api.campusMap().listen((r) {
      if (mounted) setState(() => _map = r);
    }));
  }

  @override
  void dispose() {
    _subscriptions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: CampusMapView(result: _map, events: widget.events),
      );
}
