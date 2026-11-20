import 'dart:convert';

import 'package:family_health/core/theme.dart';
import 'package:family_health/services/app_update.dart';
import 'package:family_health/ui/screens/update_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
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

class _MeteredUpdate extends AppUpdateService {
  int approvals = 0;

  @override
  Future<void> useMobileData() async {
    approvals++;
  }
}

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

  testWidgets('update status shows fallback size before authorizing mobile data',
      (tester) async {
    final updater = _MeteredUpdate()
      ..installedVersion = '1.0.9'
      ..installedBuild = 11
      ..available = const UpdateInfo(
        versionName: '1.0.9',
        buildNumber: 12,
        apkUrl: 'https://github.com/example/update.apk',
        notes: '',
        bytes: 42 * 1024 * 1024,
        sha256: 'apk',
        downloadHash: 'apk',
      )
      ..stage = UpdateStage.waiting
      ..usingFullApk = true
      ..waitingForUnmetered = true
      ..downloadElapsed = const Duration(seconds: 70);
    addTearDown(updater.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppUpdateService>.value(
      value: updater,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const UpdateStatusScreen(),
      ),
    ));
    expect(find.text('Waiting for Wi-Fi or another unmetered connection'), findsOneWidget);
    expect(find.text('Using the full APK.'), findsOneWidget);
    final mobileButton = find.widgetWithText(FilledButton, 'Use mobile data');
    await tester.ensureVisible(mobileButton);
    await tester.tap(mobileButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('42.00 MiB download'), findsOneWidget);
    expect(updater.approvals, 0);
    await tester.tap(find.widgetWithText(TextButton, 'Use mobile data'));
    await tester.pumpAndSettle();
    expect(updater.approvals, 1);
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
