import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppSupportFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The scraped snapshots live under Application Support and can all be
  /// fetched again, so they do not belong in an iCloud or device backup
  /// (App Store guideline 2.23). The directory is created here first so the
  /// flag is set before Dart writes anything into it.
  private func excludeAppSupportFromBackup() {
    let fileManager = FileManager.default
    guard var url = fileManager.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return }
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
