/// The Android target, before there is a device to try it on.
///
/// The project was created Linux only, so android/ did not exist at all. These
/// guard the parts of that platform that fail silently rather than loudly:
/// a missing permission is not a build error, it is an app that launches fine
/// and then cannot reach anything.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('the release manifest asks for network access', () {
    // Flutter writes INTERNET into the debug and profile manifests only. A
    // release build without it launches, shows its cached empty state, and
    // every scrape fails with nothing to explain why. The entire app is one
    // device scraping RIT, so this is the single most important line here.
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('it is called TigerHub, not tigerhub', () {
    expect(manifest, contains('android:label="TigerHub"'));
  });

  test('the application id matches the desktop one', () {
    // dev.colewiz.tigerhub is also the Linux window class, and the recon notes
    // record that guessing "tigerhub" instead wasted time before.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "dev.colewiz.tigerhub"'));
    expect(gradle, contains('namespace = "dev.colewiz.tigerhub"'));
  });

  test('every launcher density has a real icon', () {
    // Generated from the 512px master, so nothing is upscaled.
    const buckets = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final bucket in buckets.keys) {
      final icon = File(
        'android/app/src/main/res/mipmap-$bucket/ic_launcher.png',
      );
      expect(icon.existsSync(), isTrue, reason: bucket);
      expect(
        icon.lengthSync(),
        greaterThan(500),
        reason: '$bucket looks like a placeholder',
      );
    }
  });

  test('the Linux platform is still declared', () {
    // flutter create --platforms=android rewrote .metadata and dropped the
    // linux entry, which would confuse a later migration into thinking this
    // was never a desktop app.
    final metadata = File('.metadata').readAsStringSync();
    expect(metadata, contains('platform: android'));
    expect(metadata, contains('platform: linux'));
  });
}
