import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A file another app shared to Family Health (Share → Family Health).
class SharedFile {
  const SharedFile({required this.path, required this.mime, required this.name});
  final String path, mime, name;
  bool get isImage => mime.startsWith('image/');
}

/// Receives files shared from Photos, WhatsApp, Gmail… (Android). The activity
/// copies them into the app's cache; this holds them until the app can open the
/// upload flow (after setup and the lock screen).
class ShareInbox extends ChangeNotifier {
  ShareInbox._();
  static final instance = ShareInbox._();
  static const _channel = MethodChannel('family_health/share');

  List<SharedFile> _pending = [];
  bool get hasPending => _pending.isNotEmpty;

  void init() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await _fetch();
    });
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>('takeShared');
      if (list == null || list.isEmpty) return;
      _pending = [
        for (final m in list) SharedFile(path: m['path'] as String, mime: m['mime'] as String, name: m['name'] as String),
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('Share inbox: $e');
    }
  }

  /// Hands over the waiting files (once).
  List<SharedFile> take() {
    final p = _pending;
    _pending = [];
    return p;
  }
}
