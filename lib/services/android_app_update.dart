import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_update.dart';

/// The Android worker owns the transfer. Flutter observes its durable state
/// while visible and hands the verified file to the installer on user request.
class AndroidAppUpdateService extends AppUpdateService
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('family_health/update');
  Timer? _timer;
  Completer<void>? _pending;
  bool _observing = false;
  bool _visible = true;
  bool _disposed = false;
  bool _initialized = false;

  @override
  bool get supportsScheduling => true;

  @override
  Future<void> check({bool force = false}) async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (!_initialized) await _run('initialize');
    if (force && _initialized) await _run('check');
  }

  @override
  Future<void> dismiss() => _run('dismiss');

  @override
  Future<void> setAutomatic(bool enabled) => _run('automatic', enabled);

  @override
  Future<void> useMobileData() async {
    final hash = available?.downloadHash;
    if (hash != null) await _run('metered', hash);
  }

  @override
  Future<void> downloadAndInstall() async {
    final info = available;
    if (info == null) return;
    while (_pending != null) {
      await _pending!.future;
    }
    if (_disposed || info.sha256 != available?.sha256) return;
    if (stage != UpdateStage.ready) {
      if (!busy) await _run('start');
      return;
    }
    _pending = Completer<void>();
    _timer?.cancel();
    stage = UpdateStage.openingInstaller;
    error = null;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('install', info.sha256);
    } catch (e) {
      error = e.toString();
    } finally {
      _pending!.complete();
      _pending = null;
      await _run('snapshot');
    }
  }

  Future<void> _run(String method, [Object? argument]) async {
    while (_pending != null) {
      if (method == 'snapshot') return;
      await _pending!.future;
    }
    if (_disposed) return;
    _pending = Completer<void>();
    _timer?.cancel();
    if (method == 'check') {
      stage = UpdateStage.checking;
      notifyListeners();
    }
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        method,
        argument,
      );
      if (data == null || _disposed) return;
      if (method == 'initialize') _initialized = true;
      if (method == 'check') checkFailed = false;
      installedBuild = data['installedBuild'] as int?;
      installedVersion = data['installedVersion'] as String?;
      upToDate = data['upToDate'] == true;
      automatic = data['automatic'] == true;
      notificationsEnabled = data['notificationsEnabled'] == true;
      waitingForUnmetered = data['waitingForUnmetered'] == true;
      retrying = data['retrying'] == true;
      usingFullApk = data['fallback'] == true;
      final checkedAt = data['lastCheck'] as int? ?? 0;
      lastSuccessfulCheck = checkedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(checkedAt)
          : null;
      final elapsed = data['transferMillis'] as int?;
      downloadElapsed = elapsed != null
          ? Duration(milliseconds: elapsed)
          : null;
      downloadComplete = data['transferComplete'] == true;
      final verified = data['verificationMillis'] as int? ?? -1;
      verificationElapsed = verified >= 0
          ? Duration(milliseconds: verified)
          : null;
      final raw = data['release'] as String?;
      available = null;
      if (raw != null) {
        final release = jsonDecode(raw) as Map<String, dynamic>;
        final apk = release['apk'];
        final transfer = release['download'];
        available = UpdateInfo(
          versionName: release['version'],
          buildNumber: release['build'],
          notes: release['notes'],
          apkUrl: transfer['url'],
          bytes: transfer['size'],
          apkBytes: apk['size'],
          sha256: apk['hash'],
          downloadHash: transfer['hash'],
        );
      }
      stage = UpdateStage.values.byName(data['stage'] as String);
      if (stage != UpdateStage.ready || method != 'snapshot') {
        error = data['error'] as String?;
      }
      received = data['received'] as int? ?? 0;
      progress = available == null
          ? 0
          : (received / available!.bytes).clamp(0, 1).toDouble();
    } catch (e) {
      error = e.toString();
      checkFailed = method == 'check' || method == 'initialize';
      stage = UpdateStage.error;
    } finally {
      _pending!.complete();
      _pending = null;
      if (!_disposed) {
        notifyListeners();
        if (_visible) {
          _timer = Timer(
            Duration(seconds: showingProgress ? 2 : 15),
            () => _run(_initialized ? 'snapshot' : 'initialize'),
          );
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_visible) unawaited(_run('snapshot'));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
