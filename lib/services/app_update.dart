import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Family Health isn't on the Play Store, so updates are published as
/// GitHub Releases instead. This checks the latest release's tag —
/// `v<version>+<build>`, the same format as pubspec.yaml's `version:` line —
/// and, if its build number is higher than what's installed, offers to
/// download the new APK and hand it to Android's installer, all in-app.
const _kOwner = 'Indla26v';
const _kRepo = 'family-health-app';
const _kApkAssetName = 'FamilyHealth.apk';
const _kCheckEvery = Duration(hours: 20);
const _kLastCheckKey = 'fh_update_last_check';
const _kDismissedKey = 'fh_update_dismissed_build';

class UpdateInfo {
  const UpdateInfo({required this.versionName, required this.buildNumber, required this.apkUrl, required this.notes});
  final String versionName;
  final int buildNumber;
  final String apkUrl;
  final String notes;
}

enum UpdateStage { idle, checking, downloading, error }

class AppUpdateService extends ChangeNotifier {
  UpdateInfo? available;
  UpdateStage stage = UpdateStage.idle;
  double progress = 0; // 0..1 while downloading
  String? error;
  int? installedBuild;
  String? installedVersion;

  /// Call once at startup (respects the cooldown so it doesn't hit GitHub on
  /// every launch); pass [force] for the manual "Check for updates" button.
  Future<void> check({bool force = false}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      installedBuild = int.tryParse(info.buildNumber) ?? 0;
      installedVersion = info.version;
      final sp = await SharedPreferences.getInstance();
      if (!force) {
        final last = sp.getInt(_kLastCheckKey);
        if (last != null && DateTime.now().millisecondsSinceEpoch - last < _kCheckEvery.inMilliseconds) return;
      }
      stage = UpdateStage.checking;
      notifyListeners();
      final r = await http
          .get(Uri.parse('https://api.github.com/repos/$_kOwner/$_kRepo/releases/latest'), headers: {'accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 12));
      await sp.setInt(_kLastCheckKey, DateTime.now().millisecondsSinceEpoch);
      if (r.statusCode != 200) {
        stage = UpdateStage.idle;
        notifyListeners();
        return;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String?) ?? '';
      // Tag looks like "v1.0.1+2" — the build number after '+' is what decides "newer".
      final m = RegExp(r'^v?(.+)\+(\d+)$').firstMatch(tag);
      final assets = (j['assets'] as List?) ?? const [];
      Map<String, dynamic>? apkAsset;
      for (final a in assets) {
        if (a is Map<String, dynamic> && a['name'] == _kApkAssetName) apkAsset = a;
      }
      if (m == null || apkAsset == null) {
        available = null;
        stage = UpdateStage.idle;
        notifyListeners();
        return;
      }
      final buildNumber = int.parse(m.group(2)!);
      final dismissed = sp.getInt(_kDismissedKey) ?? 0;
      available = (buildNumber > installedBuild! && buildNumber > dismissed)
          ? UpdateInfo(versionName: m.group(1)!, buildNumber: buildNumber, apkUrl: apkAsset['browser_download_url'] as String, notes: ((j['body'] as String?) ?? '').trim())
          : null;
      stage = UpdateStage.idle;
      notifyListeners();
    } catch (e) {
      debugPrint('Update check failed: $e');
      stage = UpdateStage.idle;
      notifyListeners();
    }
  }

  /// Hide the banner for this release; it reappears once a newer one ships.
  Future<void> dismiss() async {
    final info = available;
    if (info == null) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kDismissedKey, info.buildNumber);
    available = null;
    notifyListeners();
  }

  /// Downloads the new APK (with progress) and opens Android's installer.
  Future<void> downloadAndInstall() async {
    final info = available;
    if (info == null) return;
    stage = UpdateStage.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final client = http.Client();
      final resp = await client.send(http.Request('GET', Uri.parse(info.apkUrl)));
      if (resp.statusCode != 200) throw Exception('Download failed (HTTP ${resp.statusCode})');
      final total = resp.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/FamilyHealth-update.apk');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      client.close();
      stage = UpdateStage.idle;
      notifyListeners();
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        error = result.message;
        stage = UpdateStage.error;
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
      stage = UpdateStage.error;
      notifyListeners();
    }
  }
}
