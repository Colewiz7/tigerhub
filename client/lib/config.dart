/// Build time configuration.
///
/// There is no server any more. The app scrapes RIT directly on the device, so
/// there is no base URL to point anywhere and no homelab to depend on.
///
/// [apiBaseUrl] survives for one purpose: pointing the app at a running
/// FastAPI instance to compare the two implementations while the port is being
/// checked. It is empty by default, which selects the local backend.
///
///   flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8000
library;

class AppConfig {
  const AppConfig._();

  /// Empty means "scrape locally", which is the normal case.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get usesRemoteBackend => apiBaseUrl.isNotEmpty;

  /// Shown on the about screen and in the footer. Required by the project.
  static const String disclaimer =
      'Not affiliated with, endorsed by, or officially connected to Rochester '
      'Institute of Technology. Student built and student maintained.';

  static const String appName = 'TigerHub';
}
