import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../services/importer.dart';
import '../services/reminders.dart' show navigatorKey;
import '../services/share_inbox.dart';
import '../services/sync_service.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'screens/upload.dart';
import 'screens/who_uses.dart';
import 'screens/delete_everything.dart';

/// Decides what to show first: sign-in (until signed in), "restore or start new?" (after
/// Delete everything), setup, lock screen,
/// "who uses this phone?" (once per sign-in), or the app.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  bool _ready = false, _delivering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShareInbox.instance.addListener(_deliverShare);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareInbox.instance.removeListener(_deliverShare);
    super.dispose();
  }

  /// Files shared to the app (Share → Family Health) open the upload flow, once the
  /// app is set up and unlocked: shared photos are the pages of one report; each
  /// PDF is a report of its own. The person is chosen there.
  Future<void> _deliverShare() async {
    if (!_ready || _delivering || !ShareInbox.instance.hasPending) return;
    _delivering = true;
    try {
      final shared = ShareInbox.instance.take();
      final photos = [for (final f in shared) if (f.isImage) await File(f.path).readAsBytes()];
      final files = <PickedFile>[
        if (photos.isNotEmpty) PickedFile('scan.pdf', await ImportService.pdfFromPhotos(photos), photos: photos),
        for (final f in shared) if (!f.isImage) PickedFile(f.name.toLowerCase().endsWith('.pdf') ? f.name : '${f.name}.pdf', await File(f.path).readAsBytes()),
      ];
      if (files.isNotEmpty) await navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => UploadScreen(shared: files)));
    } catch (e) {
      debugPrint('Opening shared files failed: $e');
    } finally {
      _delivering = false;
    }
  }

  /// Re-lock after the app has been in the background for a minute.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = context.read<AppStore>();
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (s.prefs.lockEnabled && _pausedAt != null && DateTime.now().difference(_pausedAt!) > const Duration(minutes: 1)) {
        s.unlocked = false;
        s.changed();
      }
      _pausedAt = null;
      // Catching up with the web on resume is SyncService's job (it watches the lifecycle too).
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>();
    final sync = context.watch<SyncService?>();
    _ready = false; // shared files wait until the screens below are past
    // An account is required. Signing in first lets an existing family's records arrive before setup.
    if (sync != null && !sync.signedIn) return const LoginScreen();
    // After "Delete everything", the owner first chooses: restore the backup or start new.
    if (sync != null && sync.pendingBackup != null) return const RestoreChoiceScreen();
    if (!s.isSetUp && sync != null && sync.signedIn && sync.syncing) return const _Syncing();
    if (!s.isSetUp) return const OnboardingScreen();
    if (s.prefs.lockEnabled && !s.unlocked) return const LockScreen();
    if (!s.prefs.deviceUserAsked && s.members.isNotEmpty) return const WhoUsesScreen();
    _ready = true;
    if (ShareInbox.instance.hasPending) WidgetsBinding.instance.addPostFrameCallback((_) => _deliverShare());
    return const HomeShell();
  }
}

class _Syncing extends StatelessWidget {
  const _Syncing();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Getting your family’s records…', style: TextStyle(fontSize: 16))])),
      );
}
