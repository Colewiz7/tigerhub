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
    // Built-in palette unless the user has opted in to following the
    // wallpaper. This runs on many different desktops.
    _scheme = SchemeController()..restore();
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
            // Both modes are generated from the same seed and follow the
            // system, since not everyone runs a dark desktop.
            theme: AppTheme.from(
              state.isDynamic
                  ? state.scheme
                  : SchemeController.builtIn(Brightness.light),
            ),
            darkTheme: AppTheme.from(
              state.isDynamic
                  ? state.scheme
                  : SchemeController.builtIn(Brightness.dark),
            ),
            themeMode: ThemeMode.system,
            home: AppShell(api: _api, scheme: _scheme),
          );
        },
      );
}
