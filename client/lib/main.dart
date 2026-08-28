import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'config.dart';
import 'services/api.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_theme.dart';

void main() => runApp(const TigerHubApp());

class TigerHubApp extends StatefulWidget {
  const TigerHubApp({super.key});

  @override
  State<TigerHubApp> createState() => _TigerHubAppState();
}

class _TigerHubAppState extends State<TigerHubApp> {
  final _api = ApiClient();
  late final SchemeController _scheme;

  @override
  void initState() {
    super.initState();
    _scheme = SchemeController(
      forceSeed: SchemeController.forceSeedFromEnvironment,
    )..load();
  }

  @override
  void dispose() {
    _api.dispose();
    _scheme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _scheme,
        builder: (context, _) {
          final state = _scheme.state;
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.from(state.scheme),
            home: AppShell(api: _api, scheme: _scheme),
          );
        },
      );
}
