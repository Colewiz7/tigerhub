import 'package:flutter/material.dart';

import 'config.dart';
import 'app_shell.dart';
import 'services/api.dart';
import 'theme/app_theme.dart';

void main() => runApp(const TigerHubApp());

class TigerHubApp extends StatefulWidget {
  const TigerHubApp({super.key});

  @override
  State<TigerHubApp> createState() => _TigerHubAppState();
}

class _TigerHubAppState extends State<TigerHubApp> {
  final _api = ApiClient();

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AppShell(api: _api),
      );
}
