import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/app_update.dart';
import '../../services/pdf_export.dart';
import '../../services/reminders.dart';
import '../../services/sync_service.dart';
import '../widgets/common.dart';
import '../widgets/update_ui.dart';
import 'lock_screen.dart';
import 'login_screen.dart';
import 'delete_everything.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _backup(BuildContext context, AppStore s) async {
    final bytes = Uint8List.fromList(utf8.encode(s.exportJson()));
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await FilePicker.saveFile(fileName: 'family-health-backup-$stamp.json', bytes: bytes, mimeType: 'application/json', dialogTitle: 'Save backup');
    if (saved != null) {
      s.setPref((p) => p.lastBackup = DateTime.now());
      if (context.mounted) toast(context, 'Backup saved');
    }
  }

  Future<void> _exportPdf(BuildContext context, AppStore s) async {
    var m = s.currentUser;
    if (s.visibleMembers.length > 1) {
      final pick = await showDialog<Member>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('Whose summary?'), children: [
          for (final x in s.visibleMembers) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, x), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [MemberAvatar(x, size: 36), const SizedBox(width: 12), Text(x.name, style: const TextStyle(fontSize: 16))]))),
        ]),
      );
      if (pick == null) return;
      m = pick;
    }
    final bytes = await buildSummaryPdf(s, m);
    final saved = await FilePicker.saveFile(fileName: 'health-summary-${m.name.toLowerCase()}.pdf', bytes: bytes, mimeType: 'application/pdf', dialogTitle: 'Save health summary');
    if (saved != null && context.mounted) toast(context, 'Summary saved');
  }

  static String _accessName(String a) => switch (a) { 'owner' => 'Owner', 'admin' => 'Admin', 'member' => 'Member', _ => 'Viewer (read-only)' };

  Future<void> _lockToggle(BuildContext context, AppStore s, bool on) async {
    if (!on) {
      if (await confirmDialog(context, 'Turn off app lock?', 'Anyone who opens this phone could see the health records.', yes: 'Turn off')) {
        s.setPref((p) => p.lockEnabled = false);
      }
      return;
    }
    final pin = await showModalBottomSheet<String>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const PinSetupSheet());
    if (pin != null) {
      s.setPin(pin);
      s.setPref((p) => p.lockEnabled = true);
      s.unlocked = true;
      if (context.mounted) toast(context, 'App lock is on');
    }
  }

  Future<void> _whoUses(BuildContext context, AppStore s) async {
    final pick = await showDialog<Member>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Who uses this phone?'), children: [
        for (final x in s.members)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, x),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [MemberAvatar(x, size: 36), const SizedBox(width: 12), Expanded(child: Text(x.name, style: const TextStyle(fontSize: 16))), if (x.id == s.prefs.deviceUserId) const Icon(Icons.check_rounded)])),
          ),
      ]),
    );
    if (pick != null) {
      s.setPref((p) => p.deviceUserId = pick.id);
      s.selectedId = null;
      s.changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final updates = context.watch<AppUpdateService?>();
    final c = context.c;
    final p = s.prefs;

    Widget group(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(tr(title).toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: c.textSecondary))),
          SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), child: Column(children: [for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider1(), rows[i]]])),
        ]);

    Widget nav(IconData icon, String title, String sub, VoidCallback onTap, {Widget? trailing}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(children: [
              IconBadge(icon, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), Text(sub, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 18 / 13))])),
              ?trailing,
              Icon(Icons.chevron_right_rounded, color: c.textSecondary),
            ]),
          ),
        );

    Widget inline(IconData icon, String title, Widget control) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(children: [
            IconBadge(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            SizedBox(width: 190, child: control),
          ]),
        );

    Widget segmented(List<(String, String)> opts, String value, ValueChanged<String> on) => Container(
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            for (final (k, l) in opts)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == k,
                  label: l,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => on(k),
                    child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: value == k ? c.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Text(l, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: value == k ? c.accent : c.textSecondary))),
                  ),
                ),
              ),
          ]),
        );

    final server = p.serverHost.trim();
    final sync = context.watch<SyncService?>();
    final acct = sync?.account;
    String syncLine() {
      if (sync == null || acct == null) return 'Not signed in';
      if (sync.syncing) return 'Syncing…';
      if (sync.needsSignIn) return 'Sign in again to sync';
      final st = s.sync;
      final pending = st.pendingCount;
      final when = st.lastSync == null ? 'not synced yet' : 'last synced ${ago(st.lastSync!.toLocal())}';
      final off = sync.offline ? ' · offline' : '';
      final err = st.lastError == null ? '' : ' · ${st.lastError}';
      return '$when${pending > 0 ? ' · $pending change${pending == 1 ? '' : 's'} waiting' : ''}$off$err';
    }

    return PageBody(
      header: ScreenHeader(title: tr('Settings'), back: true),
      spacing: 20,
      children: [
        group('Account & sync', [
          if (acct == null)
            nav(Icons.cloud_off_rounded, 'Not syncing · sign in', 'Records are only on this phone', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen(fromSettings: true))))
          else ...[
            nav(Icons.cloud_done_rounded, acct.email, '${_accessName(acct.access)} · ${syncLine()}', () => sync?.syncNow(full: true), trailing: sync != null && sync.syncing ? const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null),
            if (s.sync.rejected.isNotEmpty)
              nav(Icons.sync_problem_rounded, '${s.sync.rejected.length} change${s.sync.rejected.length == 1 ? '' : 's'} not saved online',
                  'Server said: ${s.sync.rejected.values.first} · tap to retry', () => sync?.syncNow(full: true)),
            if (sync != null && sync.needsSignIn)
              nav(Icons.login_rounded, 'Sign in again', 'Sync is paused', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen(fromSettings: true)))),
            nav(Icons.logout_rounded, 'Sign out', 'Records stay on this phone', () async {
              if (!await confirmDialog(context, 'Sign out?', 'Records stay on this phone. Unsynced changes wait until you sign in.', yes: 'Sign out')) return;
              await sync?.signOut();
            }),
          ],
        ]),
        group('Appearance & language', [
          inline(Icons.translate_rounded, tr('Language'), segmented([('en', 'English'), ('te', 'తెలుగు')], p.lang, s.setLang)),
          inline(Icons.contrast_rounded, 'Theme', segmented([('system', 'Auto'), ('light', 'Light'), ('dark', 'Dark')], p.darkMode, (v) => s.setPref((x) => x.darkMode = v))),
          SwitchRow(icon: Icons.format_size_rounded, title: 'Large text', subtitle: 'Everything 20% bigger', value: p.largeText, onChanged: (v) => s.setPref((x) => x.largeText = v)),
        ]),
        if (kMedicinesEnabled) group('Reminders', [
          SwitchRow(icon: Icons.volume_up_rounded, title: 'Voice reminders', subtitle: 'Reads medicine names in Telugu', value: p.voice, onChanged: (v) => s.setPref((x) => x.voice = v)),
          nav(Icons.notifications_rounded, 'Reminder sound', 'Alarm + vibrate · tap to allow', () async {
            final ok = await Reminders.requestPermission();
            if (context.mounted) toast(context, ok ? 'Reminders are allowed' : (Reminders.supported ? 'Allow notifications in Android settings to get reminders' : 'Reminders work on the Android phone'));
          }),
          SwitchRow(icon: Icons.group_rounded, title: 'Alert admin on missed dose', subtitle: server.isEmpty ? 'Needs the home server' : 'After 30 min', value: p.alertAdmin, onChanged: (v) => s.setPref((x) => x.alertAdmin = v)),
        ]),
        group('Privacy & data', [
          SwitchRow(icon: Icons.lock_rounded, title: 'App lock', subtitle: 'Fingerprint, PIN as backup', value: p.lockEnabled, onChanged: (v) => _lockToggle(context, s, v)),
          nav(Icons.shield_rounded, 'Backup', p.lastBackup == null ? 'No backup yet' : 'Last backup ${ago(p.lastBackup!)}', () => _backup(context, s), trailing: p.lastBackup == null ? null : StatusPill(label: 'OK', tone: 'ok')),
          nav(Icons.download_rounded, 'Export health summary (PDF)', 'For a doctor visit', () => _exportPdf(context, s)),
          nav(Icons.person_rounded, 'Who uses this phone', s.currentUser.name, () => _whoUses(context, s)),
        ]),
        if (updates != null)
          group('About', [
            nav(
              Icons.system_update_rounded,
              'Check for updates',
              updates.stage == UpdateStage.checking
                  ? 'Checking…'
                  : (updates.available != null
                      ? 'Update available: v${updates.available!.versionName}'
                      : 'You’re on the latest version${updates.installedVersion == null ? '' : ' (v${updates.installedVersion})'}'),
              () async {
                await updates.check(force: true);
                if (!context.mounted) return;
                final info = updates.available;
                if (info != null) {
                  showUpdateSheet(context, updates, info);
                } else {
                  toast(context, 'You’re on the latest version');
                }
              },
              trailing: updates.stage == UpdateStage.checking
                  ? const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : (updates.available != null ? const StatusPill(label: 'New', tone: 'warn') : null),
            ),
          ]),
        if (acct != null && acct.isOwner)
          group('Start over', [
            nav(Icons.delete_forever_rounded, 'Delete everything', 'Family records everywhere · backup kept 6 months', () => deleteEverything(context)),
          ]),
        Text('Insights describe trends only. Not medical advice.', style: TextStyle(fontSize: 14, color: c.textSecondary, height: 20 / 14)),
      ],
    );
  }
}

/// Choose a PIN, then enter it again. Pops with the PIN, or null if dismissed.
class PinSetupSheet extends StatefulWidget {
  const PinSetupSheet({super.key});
  @override
  State<PinSetupSheet> createState() => _PinSetupState();
}

class _PinSetupState extends State<PinSetupSheet> {
  String first = '', cur = '';
  bool mismatch = false;

  void _on(String v) {
    setState(() {
      cur = v;
      mismatch = false;
    });
    if (v.length == 4) {
      if (first.isEmpty) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            setState(() {
              first = v;
              cur = '';
            });
          }
        });
      } else if (v == first) {
        Navigator.of(context).pop(v);
      } else {
        setState(() {
          first = '';
          cur = '';
          mismatch = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(first.isEmpty ? 'Choose a 4-digit PIN' : 'Enter it once more', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SizedBox(height: 22, child: mismatch ? Text('Those didn’t match. Start again.', style: TextStyle(fontSize: 14, color: c.danger, fontWeight: FontWeight.w600)) : null),
          const SizedBox(height: 12),
          PinPad(value: cur, onChanged: _on),
        ]),
      ),
    );
  }
}
