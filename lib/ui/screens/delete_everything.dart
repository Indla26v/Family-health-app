import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/api_client.dart';
import '../../services/importer.dart';
import '../../services/sync_service.dart';
import '../widgets/common.dart';

/// "Delete everything" (family owner): the family's records go everywhere, online and on
/// every phone, made safe against a mis-tap:
///  1. it asks first;
///  2. it syncs, so the cloud backup has this phone's latest changes too (and warns
///     about anything that couldn't be saved online);
///  3. it needs the 6-digit code emailed to the owner;
///  4. the server saves a compressed backup in the cloud (kept 6 months), then deletes.
/// This phone is then cleared and signed out; the next sign-in asks "Restore or start new?".
Future<void> deleteEverything(BuildContext context) async {
  final s = readStore(context);
  final sync = context.read<SyncService?>();
  if (sync == null || !sync.signedIn || !(sync.account?.isOwner ?? false)) {
    toast(context, 'Only the family owner can delete everything.', ok: false);
    return;
  }
  if (!await confirmDialog(
    context,
    'Delete everything?',
    'Deletes every person, report, reading, medicine and appointment of your family, online and on every phone. '
        'A backup is saved in the cloud first: when you sign in again you can restore it, or start new. It is kept for 6 months.',
    yes: 'Continue',
  )) {
    return;
  }
  if (!context.mounted) return;

  // Make sure the backup has everything from this phone.
  await sync.syncNow(full: true);
  if (!context.mounted) return;
  if (sync.offline || sync.needsSignIn) {
    toast(context, sync.offline ? 'Connect to the internet first.' : 'Sign in again first.', ok: false);
    return;
  }
  final unsaved = s.sync.pendingCount + s.sync.rejected.length;
  if (unsaved > 0 &&
      !await confirmDialog(context, 'Not everything is saved online',
          '$unsaved change${unsaved == 1 ? '' : 's'} on this phone ${unsaved == 1 ? 'isn’t' : 'aren’t'} saved online, so ${unsaved == 1 ? 'it' : 'they'} won’t be in the backup.',
          yes: 'Delete anyway')) {
    return;
  }
  if (!context.mounted) return;

  final deleted = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _DeleteCodeDialog(api: sync.api));
  if (deleted != true || !context.mounted) return;

  await ImportService.wipe();
  await sync.signOut();
  s.deleteEverything();
  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Emails the code when it opens; "Delete everything" sends it with the delete request.
/// Pops true once the server has saved the backup and deleted the records.
class _DeleteCodeDialog extends StatefulWidget {
  const _DeleteCodeDialog({required this.api});
  final ApiClient api;
  @override
  State<_DeleteCodeDialog> createState() => _DeleteCodeDialogState();
}

class _DeleteCodeDialogState extends State<_DeleteCodeDialog> {
  final _code = TextEditingController();
  String? _sentTo, _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _message(Object e) => e is ApiException ? e.message : e is OfflineException ? 'Can’t reach the server. Check your internet.' : e is SessionExpiredException ? 'Sign in again first.' : 'Something went wrong: $e';

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final to = await widget.api.requestDeleteCode();
      if (mounted) setState(() => _sentTo = to);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deleteEverything(_code.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      title: const Text('Enter the code from your email'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _sentTo == null ? (_busy ? 'Sending a code to your email…' : 'The code couldn’t be sent.') : 'We emailed a 6-digit code to $_sentTo. It works for 10 minutes.',
          style: TextStyle(fontSize: 15, color: c.textSecondary),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          enabled: _sentTo != null && !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          autofillHints: const [AutofillHints.oneTimeCode],
          style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
          onSubmitted: (_) => _busy ? null : _delete(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(fontSize: 14, color: c.danger, fontWeight: FontWeight.w600)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: _busy ? null : _send, child: const Text('Send again')),
        TextButton(
          onPressed: _busy || _sentTo == null ? null : _delete,
          child: Text('Delete everything', style: TextStyle(fontWeight: FontWeight.w700, color: _busy || _sentTo == null ? null : c.danger)),
        ),
      ],
    );
  }
}

/// Asked by the app after signing in, while a "Delete everything" backup is waiting:
/// bring the family's records back, or start with an empty family.
class RestoreChoiceScreen extends StatefulWidget {
  const RestoreChoiceScreen({super.key});
  @override
  State<RestoreChoiceScreen> createState() => _RestoreChoiceScreenState();
}

class _RestoreChoiceScreenState extends State<RestoreChoiceScreen> {
  bool _busy = false;
  String? _error;

  static const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return d == null ? '' : '${d.day} ${_mo[d.month - 1]} ${d.year}';
  }

  /// "4 people, 63 reports, 1020 results" from the backup's row counts.
  static String _summary(Map<String, dynamic> counts) {
    String n(String k, String one, String many) {
      final v = (counts[k] as num?)?.toInt() ?? 0;
      return '$v ${v == 1 ? one : many}';
    }

    return [
      n('members', 'person', 'people'),
      if (((counts['documents'] as num?) ?? 0) > 0) n('documents', 'report', 'reports'),
      if (((counts['lab_results'] as num?) ?? 0) > 0) n('lab_results', 'result', 'results'),
      if (((counts['vitals'] as num?) ?? 0) > 0) n('vitals', 'reading', 'readings'),
    ].join(', ');
  }

  Future<void> _answer(bool restore) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SyncService>().answerBackup(restore: restore);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OfflineException {
      if (mounted) setState(() => _error = 'Can’t reach the server. Check your internet.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = context.watch<SyncService>().pendingBackup ?? const {};
    final counts = (b['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.fromLTRB(kSide, 40, kSide, 24), children: [
              Icon(Icons.cloud_done_rounded, size: 48, color: c.accent),
              const SizedBox(height: 12),
              const Text('Welcome back', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Your family’s records were deleted on ${_date(b['createdAt'] as String?)}. A backup was saved in the cloud: ${_summary(counts)}.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 28),
              BigButton(label: _busy ? 'Please wait…' : 'Restore my records', icon: Icons.restore_rounded, height: 52, onTap: _busy ? null : () => _answer(true)),
              const SizedBox(height: 12),
              BigButton(label: 'Start new (empty family)', secondary: true, height: 52, onTap: _busy ? null : () => _answer(false)),
              const SizedBox(height: 14),
              Text('If you start new, the backup can still be restored from the website’s Settings until ${_date(b['expiresAt'] as String?)}.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.35)),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
