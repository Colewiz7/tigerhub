import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'config.dart';
import 'services/api.dart';
import 'services/frame_monitor.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_theme.dart';
import 'widgets/phone_frame.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FrameMonitor.instance.start();
  runApp(const TigerHubApp());
}

class TigerHubApp extends StatefulWidget {
  const TigerHubApp({super.key});

  @override
  State<TigerHubApp> createState() => _TigerHubAppState();
}

class _TigerHubAppState extends State<TigerHubApp> {
  final _api = ApiClient();
  late final SchemeController _scheme;
  final _phone = PhoneMode.fromEnvironment();

  @override
  void initState() {
    super.initState();
    _scheme = SchemeController()..load();
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
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            // One theme from the stored choice. There is no darkTheme, so the
            // OS brightness is never consulted.
            theme: AppTheme.from(_scheme.scheme),
            builder: phoneModeBuilder(_phone),
            home: AppShell(api: _api, scheme: _scheme),
          );
        },
      );
}
