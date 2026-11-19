import 'dart:convert';

import 'package:family_health/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> asset(String suffix, {String? digest}) => {
  'name': 'FamilyHealth$suffix.apk',
  'browser_download_url':
      'https://github.com/example/family/releases/download/v1.0.8+6/FamilyHealth$suffix.apk',
  'size': suffix.isEmpty ? 116419158 : 43500000,
  'digest': digest ?? 'sha256:${'a' * 64}',
};

Map<String, dynamic> release(List<Map<String, dynamic>> assets) => {
  'tag_name': 'v1.0.8+6',
  'assets': assets,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Family Health',
      packageName: 'com.familyhealth.family_health',
      version: '1.0.8',
      buildNumber: '5',
      buildSignature: '',
      installerStore: null,
    );
  });

  test('chooses the preferred verified ABI APK, with universal fallback', () {
    final payload = release([
      asset(''),
      asset('-armeabi-v7a'),
      asset('-arm64-v8a'),
    ]);
    final arm64 = UpdateInfo.fromRelease(payload, ['arm64-v8a', 'armeabi-v7a']);
    expect(arm64!.apkUrl, endsWith('FamilyHealth-arm64-v8a.apk'));
    expect(arm64.bytes, 43500000);
    expect(arm64.buildNumber, 6);
    expect(UpdateInfo.fromRelease(payload, ['x86_64'])!.bytes, 116419158);
  });

  test(
    'skips invalid digests and refuses a release without a verified asset',
    () {
      final invalid = asset('-x86_64', digest: 'sha256:invalid');
      expect(
        UpdateInfo.fromRelease(release([invalid, asset('')]), [
          'x86_64',
        ])!.bytes,
        116419158,
      );
      expect(UpdateInfo.fromRelease(release([invalid]), ['x86_64']), isNull);
      final malformed = {...asset('-x86_64'), 'digest': 42};
      expect(UpdateInfo.fromRelease(release([malformed, asset('')]), ['x86_64'])?.bytes, 116419158);
    },
  );

  test(
    'manual check finds a dismissed update and distinguishes HTTP failure',
    () async {
      var status = 200;
      final updater = AppUpdateService(
        client: () => MockClient(
          (_) async => http.Response(jsonEncode(release([asset('')])), status),
        ),
        supportedAbis: () async => [],
      );
      addTearDown(updater.dispose);
      await updater.check(force: true);
      expect(updater.available!.buildNumber, 6);
      await updater.dismiss();
      expect(updater.available, isNull);
      await updater.check();
      expect(updater.available, isNull);
      await updater.check(force: true);
      expect(updater.available!.buildNumber, 6);
      status = 503;
      await updater.check(force: true);
      expect(updater.checkFailed, isTrue);
      expect(updater.upToDate, isFalse);
    },
  );
}
