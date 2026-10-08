/// The iOS target, before there is a device to try it on.
///
/// There is no Mac here, so nothing is built until CI does it. These guard the
/// files whose absence is only discovered by App Review, long after the build
/// has gone green.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/services/open_link.dart';

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  test('the bundle id matches Android and the Linux window class', () {
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = dev.colewiz.tigerhub;'));
  });

  test('it is called TigerHub, not tigerhub', () {
    expect(plist, contains('<key>CFBundleDisplayName</key>\n\t<string>TigerHub</string>'));
    expect(plist, contains('<key>CFBundleName</key>\n\t<string>TigerHub</string>'));
  });

  test('it is iPhone only', () {
    expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    expect(plist, isNot(contains('~ipad')));
  });

  test('the privacy manifest exists, is bundled, and declares no tracking', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    // App Review rejects an upload whose app uses UserDefaults with no reason.
    expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
  });

  test('the export compliance question is answered in the plist', () {
    expect(plist, contains('ITSAppUsesNonExemptEncryption'));
  });

  test('the icon has no alpha channel', () {
    // App Store Connect rejects a transparent 1024 icon.
    final bytes = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    ).readAsBytesSync();
    // PNG colour type sits at byte 25 of the IHDR chunk: 2 is RGB, 6 is RGBA.
    expect(bytes[25], 2);
  });

  test('phone numbers dial as digits only', () {
    expect(phoneUri('(585) 475-3333').toString(), 'tel:5854753333');
    expect(phoneUri('+1 585 475 3333').toString(), 'tel:+15854753333');
  });
}
