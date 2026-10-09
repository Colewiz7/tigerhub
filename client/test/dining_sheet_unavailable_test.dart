/// The dining detail sheet falls back to "hours unavailable" like the row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/dining_detail_sheet.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => {'data': <dynamic>[]};

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets('no spans left shows hours unavailable', (tester) async {
    final location = DiningLocation.fromJson({
      'id': 1,
      'name': 'Cafe',
      'today': [
        {'closes_at': '2026-03-01T17:00:00Z'},
      ],
      'is_open': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiningDetailSheet(
            location: location,
            api: ApiClient(backend: _EmptyBackend()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Closed · hours unavailable'), findsOneWidget);
  });
}
