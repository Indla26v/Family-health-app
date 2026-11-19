import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  const UpdateInfo({
    required this.versionName,
    required this.buildNumber,
    required this.apkUrl,
    required this.notes,
    required this.bytes,
    required this.sha256,
  });
  final String versionName, apkUrl, notes, sha256;
  final int buildNumber, bytes;

  String get sizeLabel => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  static UpdateInfo? fromRelease(
    Map<String, dynamic> release,
    List<String> abis,
  ) {
    final tagName = release['tag_name'];
    if (tagName is! String) return null;
    final tag = RegExp(
      r'^v?(\d+\.\d+\.\d+)\+(\d+)$',
    ).firstMatch(tagName);
    final build = int.tryParse(tag?.group(2) ?? '');
    final rawAssets = release['assets'];
    if (tag == null || build == null || build < 1 || rawAssets is! List) return null;
    final assets = rawAssets.whereType<Map<String, dynamic>>();
    final names = [
      for (final abi in abis)
        if (const ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(abi))
          'FamilyHealth-$abi.apk',
      _kApkAssetName,
    ];
    for (final name in names) {
      for (final asset in assets) {
        if (asset['name'] != name) continue;
        final downloadUrl = asset['browser_download_url'];
        final rawDigest = asset['digest'];
        if (downloadUrl is! String || rawDigest is! String) continue;
        final url = Uri.tryParse(downloadUrl);
        final digest = RegExp(
          r'^sha256:([0-9a-f]{64})$',
          caseSensitive: false,
        ).firstMatch(rawDigest);
        final bytes = asset['size'];
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            digest == null ||
            bytes is! int ||
            bytes <= 0) {
          continue;
        }
        return UpdateInfo(
          versionName: tag.group(1)!,
          buildNumber: build,
          apkUrl: url.toString(),
          notes: switch (release['body']) { String text => text.trim(), _ => '' },
          bytes: bytes,
          sha256: digest.group(1)!.toLowerCase(),
        );
      }
    }
    return null;
  }
}

enum UpdateStage { idle, checking, downloading, openingInstaller, error }

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    http.Client Function()? client,
    Future<List<String>> Function()? supportedAbis,
  }) : _client = client ?? http.Client.new,
       _supportedAbis = supportedAbis ?? _deviceAbis;

  static Future<List<String>> _deviceAbis() async {
    try {
      return await const MethodChannel(
            'family_health/update',
          ).invokeListMethod<String>('supportedAbis') ??
          [];
    } on MissingPluginException {
      return [];
    }
  }

  final http.Client Function() _client;
  final Future<List<String>> Function() _supportedAbis;
  UpdateInfo? available;
  UpdateStage stage = UpdateStage.idle;
  double progress = 0;
  String? error;
  int? installedBuild;
  String? installedVersion;
  bool checkFailed = false;
  bool upToDate = false;
  bool get busy =>
      stage == UpdateStage.checking ||
      stage == UpdateStage.downloading ||
      stage == UpdateStage.openingInstaller;

  /// Automatic checks respect the cooldown. Manual checks include dismissed builds.
  Future<void> check({bool force = false}) async {
    if (busy) return;
    stage = UpdateStage.checking;
    notifyListeners();
    http.Client? client;
    try {
      final info = await PackageInfo.fromPlatform();
      installedBuild = int.tryParse(info.buildNumber) ?? 0;
      installedVersion = info.version;
      final sp = await SharedPreferences.getInstance();
      final last = sp.getInt(_kLastCheckKey);
      if (!force &&
          last != null &&
          DateTime.now().millisecondsSinceEpoch - last <
              _kCheckEvery.inMilliseconds) {
        return;
      }
      client = _client();
      final response = await client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$_kOwner/$_kRepo/releases/latest',
            ),
            headers: {'accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw HttpException(
          'Release check failed (HTTP ${response.statusCode})',
        );
      }
      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final update = UpdateInfo.fromRelease(release, await _supportedAbis());
      if (update == null) {
        throw const FormatException(
          'No verified update package in the latest release',
        );
      }
      final dismissed = sp.getInt(_kDismissedKey) ?? 0;
      available =
          update.buildNumber > installedBuild! &&
              (force || update.buildNumber > dismissed)
          ? update
          : null;
      await sp.setInt(_kLastCheckKey, DateTime.now().millisecondsSinceEpoch);
      upToDate = update.buildNumber <= installedBuild!;
      checkFailed = false;
    } catch (e) {
      debugPrint('Update check failed: $e');
      checkFailed = true;
    } finally {
      client?.close();
      stage = UpdateStage.idle;
      notifyListeners();
    }
  }

  /// Hide the banner for this release; it reappears once a newer one ships.
  Future<void> dismiss() async {
    final info = available;
    if (info == null || busy) return;
    available = null;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kDismissedKey, info.buildNumber);
  }

  Future<bool> _verified(File file, UpdateInfo info) async =>
      await file.exists() &&
      await file.length() == info.bytes &&
      (await sha256.bind(file.openRead()).first).toString() == info.sha256;

  /// Only complete, verified files are reused. The installer verifies the signing
  /// identity against the installed app when it applies the update.
  Future<void> downloadAndInstall() async {
    final info = available;
    if (info == null || busy) return;
    stage = UpdateStage.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    http.Client? client;
    File? partial;
    IOSink? sink;
    var nextStage = UpdateStage.idle;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/FamilyHealth-${info.buildNumber}-${info.sha256.substring(0, 16)}.apk',
      );
      if (!await _verified(file, info)) {
        if (await file.exists()) await file.delete();
        partial = File('${file.path}.part');
        client = _client();
        final response = await client
            .send(http.Request('GET', Uri.parse(info.apkUrl)))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('Download failed (HTTP ${response.statusCode})');
        }
        sink = partial.openWrite();
        var received = 0;
        var lastPercent = -1;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > info.bytes) {
            throw const FormatException(
              'Update is larger than the published package',
            );
          }
          sink.add(chunk);
          final percent = received * 100 ~/ info.bytes;
          if (percent != lastPercent) {
            lastPercent = percent;
            progress = received / info.bytes;
            notifyListeners();
          }
        }
        await sink.close();
        sink = null;
        if (!await _verified(partial, info)) {
          throw const FormatException('Update checksum did not match');
        }
        await partial.rename(file.path);
      }
      stage = UpdateStage.openingInstaller;
      notifyListeners();
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) throw StateError(result.message);
    } catch (e) {
      error = '$e';
      nextStage = UpdateStage.error;
    } finally {
      client?.close();
      try {
        await sink?.close();
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (e) {
        debugPrint('Could not clean up partial update: $e');
      }
      stage = nextStage;
      notifyListeners();
    }
  }
}
