/// Build time configuration.
///
/// The API base URL is a single constant so moving from local dev to the
/// homelab is one value, not a find and replace. Override without editing
/// source:
///
///   flutter run -d linux --dart-define=API_BASE_URL=https://tigerhub.colewiz.dev
library;

class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Shown on the about screen and in the footer. Required by the project.
  static const String disclaimer =
      'Not affiliated with, endorsed by, or officially connected to Rochester '
      'Institute of Technology. Student built and student maintained.';

  static const String appName = 'TigerHub';
}
