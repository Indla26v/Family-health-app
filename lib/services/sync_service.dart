import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../data/sync_state.dart';
import 'api_client.dart';
import 'importer.dart';

/// Offline-first sync with the Family Health web app.
///
/// Everything is read and written locally first (AppStore → SharedPreferences);
/// this service only reconciles in the background:
///  1. **Track**: on every local save, each record's server-shaped data is hashed;
///     a changed hash marks it dirty with `updatedAt = now` (UTC). Removed records
///     that the server knows become tombstones.
///  2. **Pull**: `GET /api/v1/sync?since=cursor` returns rows and deletions of the
///     family newer than the cursor. A pulled row replaces the local one unless the
///     local copy is dirty and newer (last write wins).
///  3. **Push**: dirty rows and tombstones go to `POST /api/v1/sync`; the server
///     applies them with last-write-wins and returns its own copy for conflicts,
///     which is adopted locally.
///  4. **Files**: original report files are uploaded once (`PUT /api/v1/files/:id`).
/// Failures (offline, server down) leave everything dirty for the next attempt.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService(this.store, {ApiClient? api}) : api = api ?? ApiClient(TokenStore.instance);
  final AppStore store;
  final ApiClient api;
  TokenStore get tokens => api.tokens;

  bool syncing = false;
  bool needsSignIn = false;
  bool offline = false;

  /// After "Delete everything": the cloud backup the owner hasn't chosen to restore or
  /// leave yet ({id, createdAt, counts, …}). The app asks "Restore or start new?" first.
  Map<String, dynamic>? pendingBackup;
  Timer? _debounce, _periodic;
  bool _applying = false;
  bool _foreground = true;
  Future<void>? _running;

  /// Set by [signIn]: after the first pull, fold this phone's offline records into
  /// matching ones already online, so nothing is uploaded twice.
  bool _mergeAfterPull = false;

  AccountInfo? get account => tokens.account;
  bool get signedIn => tokens.hasAccount;

  /// Hook into the store and start background syncing.
  void attach() {
    // Only while an account is linked: offline-only use keeps no sync bookkeeping.
    store.beforeSave = () {
      if (!_applying && signedIn) track();
    };
    store.afterSave = () {
      if (!_applying && !syncing && signedIn && !needsSignIn && (account?.canWrite ?? false) && store.sync.pendingCount > 0) schedule();
    };
    // While the app is open, pull every minute (a cheap "anything new?" when nothing
    // changed) so edits made on the web show up without a manual refresh.
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) syncNow();
    });
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    if (signedIn) unawaited(syncNow(full: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground || !signedIn) return;
    final last = store.sync.lastSync;
    if (last == null || DateTime.now().toUtc().difference(last) > const Duration(seconds: 15)) unawaited(syncNow());
  }

  /// Push soon after local edits (debounced).
  void schedule([Duration delay = const Duration(milliseconds: 1500)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ sign in / out

  /// Signs in. If this phone holds another family's synced data, it's cleared first
  /// (never mixed). Unsynced local data is uploaded into the account's family.
  Future<AccountInfo> signIn(String base, String email, String password) async => _afterSignIn(await api.login(base, email, password));

  /// Finishes a sign-up with the emailed code: a new, empty family, signed in like [signIn].
  Future<AccountInfo> finishSignUp(String base, String email, String code) async => _afterSignIn(await api.signUpVerify(base, email, code));

  Future<AccountInfo> _afterSignIn(AccountInfo acct) async {
    final st = store.sync;
    if (st.familyId != null && st.familyId != acct.familyId) {
      store.deleteEverything();
    }
    store.migrateIdsNow();
    store.sync.familyId = acct.familyId;
    store.setPref((p) => p.deviceUserAsked = false); // ask "who uses this phone?" after this sign-in
    _mergeAfterPull = true;
    needsSignIn = false;
    notifyListeners();
    await syncNow(full: true);
    return acct;
  }

  /// "Restore or start new?" answered: restore the cloud backup (then download it all),
  /// or keep the family empty. Either way the question doesn't come back.
  Future<void> answerBackup({required bool restore}) async {
    final id = pendingBackup?['id'] as String?;
    if (id == null) return;
    if (restore) {
      await api.restoreBackup(id);
    } else {
      await api.startNew(id);
    }
    pendingBackup = null;
    notifyListeners();
    if (restore) await syncNow(full: true);
  }

  /// Signs out: revokes this phone's refresh token. Data stays on the phone.
  Future<void> signOut() async {
    await api.logout();
    needsSignIn = false;
    pendingBackup = null;
    notifyListeners();
  }

  /// Saves the Health card order (Arrange cards): on this phone at once, and on the
  /// account now if online, otherwise at the next full sync.
  Future<void> saveHealthOrder(List<String> order) async {
    store.setPref((p) => p
      ..healthOrder = order
      ..healthOrderDirty = true);
    if (!signedIn) return;
    try {
      await api.saveHealthOrder(order);
      store.setPref((p) => p.healthOrderDirty = false);
    } catch (e) {
      debugPrint('Saving card order failed, will retry: $e');
    }
  }

  /// The account's card order wins unless this phone has a change the server hasn't got yet.
  Future<void> _syncHealthOrder(AccountInfo acct) async {
    final p = store.prefs;
    if (p.healthOrderDirty) {
      try {
        await api.saveHealthOrder(p.healthOrder);
        store.setPref((p) => p.healthOrderDirty = false);
      } on ApiException catch (_) {}
    } else if (acct.healthOrder != null && !listEquals(acct.healthOrder, p.healthOrder)) {
      store.setPref((p) => p.healthOrder = List.of(acct.healthOrder!));
    }
  }

  /// Whether this phone holds synced data of a different family than [familyId].
  bool holdsOtherFamily(String familyId) => store.sync.familyId != null && store.sync.familyId != familyId;

  // ------------------------------------------------------------------ main loop

  /// Pulls and pushes. A [full] sync (app start, pull-to-refresh, tapping the
  /// account in Settings) also refreshes the account and re-sends every record the
  /// server has not accepted yet. A call while a sync is running waits for it.
  Future<void> syncNow({bool full = false}) {
    if (!signedIn) return Future.value();
    if (_running != null) return _running!;
    final run = _sync(full);
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _sync(bool full) async {
    syncing = true;
    notifyListeners();
    final st = store.sync;
    try {
      store.saveNow(); // records pending local edits
      if (full) {
        _retryRefused();
        try {
          final acct = await api.me();
          await _syncHealthOrder(acct);
          pendingBackup = acct.isOwner ? await api.pendingBackup() : null;
          if (pendingBackup != null) notifyListeners();
        } on ApiException catch (_) {
          // Older servers or transient errors: keep the cached account.
        }
      }
      await _pull();
      if (_mergeAfterPull) {
        _mergeIntoServerCopies();
        _mergeAfterPull = false;
      }
      if (account?.canWrite ?? false) {
        final again = await _push();
        await _uploadFiles();
        if (again) await _pull();
      }
      st.lastSync = DateTime.now().toUtc();
      st.lastError = null;
      offline = false;
      needsSignIn = false;
      _adoptAccountMember();
    } on OfflineException catch (e) {
      offline = true;
      debugPrint('Sync: offline ($e)');
    } on SessionExpiredException {
      needsSignIn = true;
      st.lastError = 'Sign in again to resume sync';
    } on ApiException catch (e) {
      st.lastError = e.message;
      debugPrint('Sync failed: $e');
    } catch (e, stack) {
      st.lastError = 'Sync problem: $e';
      debugPrint('Sync failed: $e\n$stack');
    } finally {
      syncing = false;
      store.saveNow();
      store.refresh();
      notifyListeners();
    }
  }

  /// After the first sync on a new phone: finish setup and pick "who uses this phone".
  void _adoptAccountMember() {
    final s = store;
    if (s.members.isEmpty) return;
    final mid = account?.memberId;
    if (s.member(s.prefs.deviceUserId) == null) {
      s.prefs.deviceUserId = (mid != null && s.member(mid) != null) ? mid : s.members.first.id;
    }
    if (!s.prefs.setupDone) s.prefs.setupDone = true;
  }

  // ------------------------------------------------------------------ first sign-in merge

  /// A phone used offline before signing in may hold the same people and reports
  /// the family already has online (for example the same PDF uploaded on the web).
  /// Those local copies are folded into the server's records instead of being
  /// uploaded a second time:
  ///  - a person with the same name → their records move to the online person;
  ///  - a report with the same person, date and values → dropped (the online one stays);
  ///  - the same check-up, reading or medicine → dropped (a later check-up date is kept).
  /// Only records the server has never seen are touched.
  @visibleForTesting
  void mergeIntoServerCopies() => _mergeIntoServerCopies();

  void _mergeIntoServerCopies() {
    final s = store, st = s.sync;
    bool online(String table, String id) => st.recs[key(table, id)]?.s ?? false;
    String norm(String x) => x.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    var changed = false;

    // People.
    final people = <String, String>{};
    for (final l in s.members.where((m) => !online('members', m.id))) {
      for (final o in s.members) {
        if (o.id != l.id && online('members', o.id) && norm(o.name) == norm(l.name)) {
          people[l.id] = o.id;
          break;
        }
      }
    }
    if (people.isNotEmpty) {
      String mid(String id) => people[id] ?? id;
      for (final x in s.docs) {
        x.memberId = mid(x.memberId);
      }
      for (final x in s.labs) {
        x.memberId = mid(x.memberId);
      }
      for (final x in s.meds) {
        x.memberId = mid(x.memberId);
      }
      for (final x in s.logs.values) {
        x.memberId = mid(x.memberId);
      }
      for (final x in s.vitals) {
        x.memberId = mid(x.memberId);
      }
      for (final x in s.appts) {
        x.memberId = mid(x.memberId);
      }
      for (final x in s.checkups) {
        x.memberId = mid(x.memberId);
      }
      if (people.containsKey(s.prefs.deviceUserId)) s.prefs.deviceUserId = people[s.prefs.deviceUserId]!;
      if (people.containsKey(s.selectedId)) s.selectedId = people[s.selectedId];
      s.members.removeWhere((m) => people.containsKey(m.id));
      changed = true;
    }

    // Reports: same person, date and set of values.
    String values(String docId) => (s.labs.where((l) => l.docId == docId).map((l) => '${l.testKey}=${l.value}').toList()..sort()).join(',');
    final docs = <String, String>{};
    for (final d in s.docs.where((d) => !online('documents', d.id))) {
      final mine = values(d.id);
      if (mine.isEmpty) continue;
      for (final o in s.docs) {
        if (o.id != d.id && online('documents', o.id) && o.memberId == d.memberId && dayKey(o.date) == dayKey(d.date) && values(o.id) == mine) {
          docs[d.id] = o.id;
          o.filePath ??= d.filePath; // keep the phone's copy of the original file
          break;
        }
      }
    }
    if (docs.isNotEmpty) {
      for (final a in s.appts) {
        if (docs.containsKey(a.takeDocId)) a.takeDocId = docs[a.takeDocId];
        if (docs.containsKey(a.prescriptionDocId)) a.prescriptionDocId = docs[a.prescriptionDocId];
      }
      s.labs.removeWhere((l) => docs.containsKey(l.docId));
      s.docs.removeWhere((d) => docs.containsKey(d.id));
      changed = true;
    }

    // Check-ups: same person and name; keep the later "last done".
    final dupChecks = <String>{};
    for (final c in s.checkups.where((c) => !online('checkups', c.id))) {
      for (final o in s.checkups) {
        if (o.id != c.id && online('checkups', o.id) && o.memberId == c.memberId && norm(o.name) == norm(c.name)) {
          if (c.last != null && (o.last == null || c.last!.isAfter(o.last!))) o.last = c.last;
          dupChecks.add(c.id);
          break;
        }
      }
    }
    if (dupChecks.isNotEmpty) {
      s.checkups.removeWhere((c) => dupChecks.contains(c.id));
      changed = true;
    }

    // Readings: same person, type, minute and values.
    final dupVitals = <String>{};
    for (final v in s.vitals.where((v) => !online('vitals', v.id))) {
      if (s.vitals.any((o) => o.id != v.id && online('vitals', o.id) && o.memberId == v.memberId && o.type == v.type && o.at.difference(v.at).inSeconds.abs() < 60 && o.a == v.a && o.b == v.b)) dupVitals.add(v.id);
    }
    if (dupVitals.isNotEmpty) {
      s.vitals.removeWhere((v) => dupVitals.contains(v.id));
      changed = true;
    }

    // Medicines: same person, name and strength; their dose history moves across.
    final meds = <String, String>{};
    for (final m in s.meds.where((m) => !online('medicines', m.id))) {
      for (final o in s.meds) {
        if (o.id != m.id && online('medicines', o.id) && o.memberId == m.memberId && norm(o.name) == norm(m.name) && norm(o.strength) == norm(m.strength)) {
          meds[m.id] = o.id;
          if (o.teluguName.isEmpty) o.teluguName = m.teluguName;
          break;
        }
      }
    }
    if (meds.isNotEmpty) {
      for (final l in s.logs.values.where((l) => meds.containsKey(l.medId)).toList()) {
        s.logs.remove(l.key);
        l.medId = meds[l.medId]!;
        s.logs.putIfAbsent(l.key, () => l);
      }
      s.meds.removeWhere((m) => meds.containsKey(m.id));
      changed = true;
    }

    if (changed) {
      debugPrint('Sync: merged offline records into the family (${people.length} people, ${docs.length} reports)');
      store.saveNow();
      store.refresh();
    }
  }

  /// Marks for sending again every record the server has never accepted and that
  /// isn't already waiting: ones it refused before (perhaps for a reason fixed since
  /// on the server), and ones older versions of the app stopped retrying silently.
  void _retryRefused() {
    final st = store.sync;
    final now = DateTime.now().toUtc();
    for (final r in st.recs.values) {
      if (!r.s && !r.d) {
        r
          ..d = true
          ..u = now;
      }
    }
    st.rejected.clear();
  }

  // ------------------------------------------------------------------ tracking

  static String _hash(Map<String, dynamic> data) => md5.convert(utf8.encode(jsonEncode(data))).toString();
  static String key(String table, String id) => '$table|$id';

  /// Records the current local state against the sync bookkeeping.
  void track() {
    final st = store.sync;
    final now = DateTime.now().toUtc();
    final cur = localRecords(store);
    for (final r in cur.values) {
      final k = key(r.table, r.id);
      final h = _hash(r.data);
      final meta = st.recs[k];
      if (meta == null) {
        st.recs[k] = SyncRec(h: h, u: now, d: true, m: r.memberId, p: r.parent);
      } else if (meta.h != h) {
        meta
          ..h = h
          ..u = now
          ..d = true
          ..m = r.memberId
          ..p = r.parent;
      }
    }
    final gone = st.recs.keys.where((k) => !cur.containsKey(k)).toList();
    for (final k in gone) {
      final meta = st.recs.remove(k)!;
      if (meta.s) {
        final i = k.indexOf('|');
        st.tombs.add(Tombstone(table: k.substring(0, i), id: k.substring(i + 1), u: now, m: meta.m, p: meta.p));
      }
    }
  }

  /// After server changes were applied locally: records them as clean (not dirty),
  /// and forgets removed records without tombstones (the server removed them).
  void _absorb(Map<String, DateTime> touched) {
    final st = store.sync;
    final cur = localRecords(store);
    for (final r in cur.values) {
      final k = key(r.table, r.id);
      final h = _hash(r.data);
      final meta = st.recs[k];
      final at = touched[k];
      if (at != null) {
        st.recs[k] = SyncRec(h: h, u: at, d: false, s: true, m: r.memberId, p: r.parent);
      } else if (meta == null) {
        st.recs[k] = SyncRec(h: h, u: DateTime.now().toUtc(), d: true, m: r.memberId, p: r.parent);
      } else if (meta.h != h) {
        meta
          ..h = h
          ..u = DateTime.now().toUtc()
          ..d = true;
      }
    }
    st.recs.removeWhere((k, _) => !cur.containsKey(k));
  }

  // ------------------------------------------------------------------ pull

  Future<void> _pull() async {
    final st = store.sync;
    for (var page = 0; page < 200; page++) {
      final j = await api.getJson('/api/v1/sync?since=${st.cursor}&limit=500');
      final changes = (j['changes'] as List? ?? []).cast<Map<String, dynamic>>();
      _applyServerChanges(changes);
      st.cursor = (j['cursor'] as num?)?.toInt() ?? st.cursor;
      store.saveNow();
      if (j['hasMore'] != true) break;
    }
  }

  void _applyServerChanges(List<Map<String, dynamic>> changes) {
    if (changes.isEmpty) return;
    final st = store.sync;
    final touched = <String, DateTime>{};
    _applying = true;
    try {
      track(); // capture local edits first, so they're not mistaken for server changes
      for (final c in changes) {
        final table = c['table'] as String;
        final id = c['id'] as String;
        final k = key(table, id);
        final meta = st.recs[k];
        if (c['op'] == 'delete') {
          final at = DateTime.parse(c['deletedAt'] as String);
          if (meta != null && meta.d && meta.u.isAfter(at)) continue; // newer local edit wins
          _removeLocal(table, id);
          st.tombs.removeWhere((t) => t.table == table && t.id == id);
        } else {
          final at = DateTime.parse(c['updatedAt'] as String);
          if (meta != null && meta.d && meta.u.isAfter(at)) continue; // newer local edit wins
          if (st.tombs.any((t) => t.table == table && t.id == id && t.u.isAfter(at))) continue; // deleted here later
          st.tombs.removeWhere((t) => t.table == table && t.id == id);
          applyUpsert(store, table, Map<String, dynamic>.from(c['data'] as Map));
          touched[k] = at;
        }
      }
      _absorb(touched);
    } finally {
      _applying = false;
    }
    store.refresh();
  }

  void _removeLocal(String table, String id) {
    final s = store;
    switch (table) {
      case 'members':
        if (s.member(id) == null) return;
        s.members.removeWhere((m) => m.id == id);
        s.docs.removeWhere((d) => d.memberId == id);
        s.labs.removeWhere((l) => l.memberId == id);
        final medIds = s.meds.where((m) => m.memberId == id).map((m) => m.id).toSet();
        s.meds.removeWhere((m) => m.memberId == id);
        s.logs.removeWhere((k, v) => v.memberId == id || medIds.contains(v.medId));
        s.vitals.removeWhere((v) => v.memberId == id);
        s.appts.removeWhere((a) => a.memberId == id);
        s.checkups.removeWhere((c) => c.memberId == id);
        if (s.selectedId == id) s.selectedId = null;
      case 'documents':
        s.docs.removeWhere((d) => d.id == id);
        s.labs.removeWhere((l) => l.docId == id);
      case 'labResults':
        s.labs.removeWhere((l) => l.id == id);
      case 'medicines':
        s.meds.removeWhere((m) => m.id == id);
        s.logs.removeWhere((k, v) => v.medId == id);
      case 'doseLogs':
        s.logs.remove(id);
      case 'vitals':
        s.vitals.removeWhere((v) => v.id == id);
      case 'appointments':
        s.appts.removeWhere((a) => a.id == id);
      case 'checkups':
        s.checkups.removeWhere((c) => c.id == id);
    }
  }

  // ------------------------------------------------------------------ push

  /// Returns true when a follow-up pull is useful (a refused delete must be restored).
  Future<bool> _push() async {
    final st = store.sync;
    track();
    final cur = localRecords(store);
    // Deletes the server cascades by itself (children of a deleted person, report or medicine).
    final goneMembers = st.tombs.where((t) => t.table == 'members').map((t) => t.id).toSet();
    final goneDocs = st.tombs.where((t) => t.table == 'documents').map((t) => t.id).toSet();
    final goneMeds = st.tombs.where((t) => t.table == 'medicines').map((t) => t.id).toSet();
    bool implied(Tombstone t) =>
        (t.table != 'members' && t.m != null && goneMembers.contains(t.m)) || (t.table == 'labResults' && goneDocs.contains(t.p)) || (t.table == 'doseLogs' && goneMeds.contains(t.p));

    final changes = <Map<String, dynamic>>[];
    final sentAt = <String, DateTime>{};
    for (final e in st.recs.entries.where((e) => e.value.d)) {
      final r = cur[e.key];
      if (r == null) continue;
      changes.add({'table': r.table, 'op': 'upsert', 'id': r.id, 'updatedAt': e.value.u.toUtc().toIso8601String(), 'data': r.data});
      sentAt[e.key] = e.value.u;
    }
    final sentTombs = <Tombstone>[];
    for (final t in List<Tombstone>.from(st.tombs)) {
      if (implied(t)) {
        st.tombs.remove(t);
        continue;
      }
      changes.add({'table': t.table, 'op': 'delete', 'id': t.id, 'updatedAt': t.u.toUtc().toIso8601String()});
      sentTombs.add(t);
    }
    if (changes.isEmpty) return false;

    var restore = false;
    for (var i = 0; i < changes.length; i += 400) {
      final batch = changes.sublist(i, i + 400 > changes.length ? changes.length : i + 400);
      final res = await api.postJson('/api/v1/sync', {'changes': batch});
      for (final a in (res['applied'] as List? ?? []).cast<Map<String, dynamic>>()) {
        final k = key(a['table'] as String, a['id'] as String);
        final meta = st.recs[k];
        if (meta != null && sentAt[k] != null && meta.u == sentAt[k]) {
          meta
            ..d = false
            ..s = true;
        }
        st.rejected.remove(k);
        st.tombs.removeWhere((t) => t.table == a['table'] && t.id == a['id'] && sentTombs.contains(t));
      }
      final adopt = <Map<String, dynamic>>[];
      for (final c in (res['conflicts'] as List? ?? []).cast<Map<String, dynamic>>()) {
        final table = c['table'] as String, id = c['id'] as String;
        final k = key(table, id);
        final server = c['server'];
        final wasDelete = sentTombs.any((t) => t.table == table && t.id == id);
        st.tombs.removeWhere((t) => t.table == table && t.id == id && sentTombs.contains(t));
        if (server is Map) {
          adopt.add({'table': table, 'op': 'upsert', 'id': id, 'updatedAt': c['updatedAt'] ?? DateTime.now().toUtc().toIso8601String(), 'data': server});
          if (wasDelete) restore = true;
        } else {
          // Refused without a server copy (invalid or not allowed): stop retrying it
          // until the next full sync, and keep the reason so Settings can show it.
          st.recs[k]?.d = false;
          st.rejected[k] = (c['reason'] as String?) ?? 'refused';
          debugPrint('Sync: ${c['table']} $id refused: ${c['reason']}');
        }
      }
      if (adopt.isNotEmpty) {
        // Make the server copy win locally.
        for (final a in adopt) {
          st.recs[key(a['table'] as String, a['id'] as String)]?.d = false;
        }
        _applyServerChanges(adopt);
      }
    }
    if (restore) st.cursor = 0; // a refused delete: re-pull so removed children come back
    store.saveNow();
    return restore;
  }

  // ------------------------------------------------------------------ files

  Future<void> _uploadFiles() async {
    if (kIsWeb) return;
    final st = store.sync;
    if (st.filesVersion < 1) {
      // Big scans used to be skipped for good; now a smaller copy is sent, so try them again.
      for (final d in store.docs) {
        final p = d.filePath;
        if (p != null && st.uploadedFiles.contains(d.id) && File(p).existsSync() && File(p).lengthSync() > ImportService.kMaxUpload) st.uploadedFiles.remove(d.id);
      }
      st.filesVersion = 1;
    }
    for (final d in store.docs) {
      final path = d.filePath;
      if (path == null || st.uploadedFiles.contains(d.id)) continue;
      final meta = st.recs[key('documents', d.id)];
      if (meta == null || !meta.s) continue; // the report itself must reach the server first
      final f = File(path);
      if (!f.existsSync()) continue;
      final mime = mimeFor(path);
      if (mime == null) continue;
      var bytes = await f.readAsBytes();
      if (bytes.length > ImportService.kMaxUpload && mime == 'application/pdf') {
        // Over the website's limit (a long photo scan): send a smaller copy, keep the original here.
        bytes = await ImportService.compactPdf(bytes) ?? bytes;
      }
      if (bytes.length > ImportService.kMaxUpload) {
        // Still too big for one request: keep the file on the phone only.
        st.uploadedFiles.add(d.id);
        continue;
      }
      final r = await api.send('PUT', '/api/v1/files/${d.id}', bytes: bytes, headers: {'content-type': mime, 'x-file-name': path.split(RegExp(r'[\\/]')).last});
      if (r.statusCode < 300 || r.statusCode == 400) st.uploadedFiles.add(d.id);
    }
  }

  /// Downloads the original file of a report added elsewhere (web, another phone)
  /// and keeps it on this phone. Returns the bytes, or null with [why] set.
  Future<(Uint8List?, String)> fetchOriginal(Doc d) async {
    if (!signedIn) return (null, 'Sign in to download the original');
    try {
      final r = await api.send('GET', '/api/v1/files/${d.id}');
      if (r.statusCode == 404) return (null, 'The original file isn’t stored online');
      if (r.statusCode >= 400) return (null, 'Couldn’t download the original (${r.statusCode})');
      final mime = (r.headers['content-type'] ?? '').split(';').first.trim();
      final ext = switch (mime) { 'image/png' => 'png', 'image/jpeg' => 'jpg', _ => 'pdf' };
      final path = await ImportService.persist(r.bodyBytes, d.id, 'report.$ext');
      final doc = store.doc(d.id);
      if (doc != null && path != null) {
        // Phone-only detail: record it without marking the report as edited.
        _applying = true;
        try {
          doc
            ..filePath = path
            ..isImage = mime.startsWith('image/');
          final k = key('documents', doc.id);
          final rec = localRecords(store)[k];
          if (rec != null) store.sync.recs[k]?.h = _hash(rec.data);
          store.sync.uploadedFiles.add(doc.id); // the server already has it
          store.saveNow();
        } finally {
          _applying = false;
        }
        store.refresh();
      }
      return (r.bodyBytes, '');
    } on OfflineException {
      return (null, 'No internet — connect to download the original');
    } on SessionExpiredException {
      return (null, 'Sign in again to download the original');
    } catch (e) {
      debugPrint('Download of ${d.id} failed: $e');
      return (null, 'Couldn’t download the original');
    }
  }

  // ------------------------------------------------------------------ mapping

  static String? mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.pdf')) return 'application/pdf';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  static Color _color(Object? v) {
    final s = (v as String? ?? '').replaceAll('#', '');
    final n = int.tryParse(s, radix: 16);
    return Color(0xFF000000 | (n ?? 0x0F766E));
  }

  static String _utc(DateTime d) => d.toUtc().toIso8601String();
  static DateTime _local(Object? v) => DateTime.parse(v as String).toLocal();
  static DateTime _day(Object? v) {
    final p = (v as String).split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static const _status = {DocStatus.parsed: 'parsed', DocStatus.needsReview: 'needs_review', DocStatus.failed: 'failed'};

  /// Every syncable local record in the server's shape, keyed `table|id`.
  static Map<String, LocalRecord> localRecords(AppStore s) {
    final out = <String, LocalRecord>{};
    void add(String table, String id, Map<String, dynamic> data, {String? memberId, String? parent}) => out[key(table, id)] = LocalRecord(table, id, data, memberId, parent);

    for (final m in s.members) {
      add('members', m.id, {
        'id': m.id, 'name': m.name, 'fullName': m.fullName, 'age': m.age, 'sex': m.sex.name, 'bloodGroup': m.bloodGroup,
        // A height the server would refuse (e.g. typed in mm) must not keep the whole person
        // and their reports off the web; it stays on this phone until corrected.
        'color': _hex(m.color), 'role': m.role.name, 'conditions': m.conditions, 'heightCm': _height(m.heightCm), 'abha': m.abha,
        'insurance': m.insurance, 'allergies': m.allergies, 'familyHistory': m.familyHistory,
        'contacts': m.contacts.map((c) => c.toJson()).toList(),
      }, memberId: m.id);
    }
    for (final d in s.docs) {
      final status = _status[d.status];
      if (status == null) continue; // still being read on this phone
      final name = d.filePath?.split(RegExp(r'[\\/]')).last;
      add('documents', d.id, {
        'id': d.id, 'memberId': d.memberId, 'lab': d.lab.isEmpty ? 'Lab report' : d.lab, 'date': dayKey(d.date), 'kind': d.kind.name, 'status': status,
        'testCount': d.testCount, 'pages': d.pages < 1 ? 1 : d.pages, 'note': d.note,
        'fileName': name, 'mimeType': d.filePath == null ? null : mimeFor(d.filePath!),
      }, memberId: d.memberId);
    }
    for (final l in s.labs) {
      add('labResults', l.id, {
        'id': l.id, 'memberId': l.memberId, 'docId': l.docId, 'testKey': l.testKey, 'value': l.value, 'unit': l.unit, 'date': dayKey(l.date),
        'lab': l.lab, 'rawName': l.rawName, 'confidence': l.confidence.clamp(0, 1), 'confirmed': l.confirmed, 'checkNote': l.checkNote, 'refText': l.refText,
      }, memberId: l.memberId, parent: l.docId);
    }
    for (final m in s.meds) {
      add('medicines', m.id, {
        'id': m.id, 'memberId': m.memberId, 'name': m.name, 'strength': m.strength, 'food': m.food.name,
        'times': m.times.map((t) => t.toJson()).toList(), 'stock': m.stock, 'tablets': m.tablets, 'refillDays': m.refillDays,
        'startDate': dayKey(m.startDate), 'active': m.active, 'forCondition': m.forCondition, 'createdAt': _utc(m.startDate),
      }, memberId: m.memberId);
    }
    for (final l in s.logs.values) {
      add('doseLogs', l.key, {'medId': l.medId, 'memberId': l.memberId, 'day': l.day, 'timeKey': l.timeKey, 'state': l.state.name, 'at': _utc(l.at)}, memberId: l.memberId, parent: l.medId);
    }
    for (final v in s.vitals) {
      add('vitals', v.id, {'id': v.id, 'memberId': v.memberId, 'type': v.type.name, 'at': _utc(v.at), 'a': v.a, 'b': v.b, 'pulse': v.pulse, 'afterMeal': v.afterMeal}, memberId: v.memberId);
    }
    for (final a in s.appts) {
      add('appointments', a.id, {
        'id': a.id, 'memberId': a.memberId, 'title': a.title, 'place': a.place, 'at': _utc(a.at), 'reason': a.reason, 'notes': a.notes,
        'takeDocId': a.takeDocId, 'prescriptionDocId': a.prescriptionDocId,
      }, memberId: a.memberId);
    }
    for (final c in s.checkups) {
      add('checkups', c.id, {'id': c.id, 'memberId': c.memberId, 'name': c.name, 'intervalMonths': c.intervalMonths, 'last': c.last == null ? null : dayKey(c.last!), 'condition': c.condition}, memberId: c.memberId);
    }
    return out;
  }

  static double? _height(double? cm) => cm != null && cm > 0 && cm <= 300 ? cm : null;
  static double _dbl(Object? v, [double fallback = 0]) => (v as num?)?.toDouble() ?? fallback;
  static int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
  static String _str(Object? v) => (v as String?) ?? '';

  static void _put<T>(List<T> list, T item, bool Function(T) same) {
    final i = list.indexWhere(same);
    if (i < 0) {
      list.add(item);
    } else {
      list[i] = item;
    }
  }

  /// Inserts or replaces one record from the server, keeping phone-only fields
  /// (file paths, pill photos, Telugu names).
  static void applyUpsert(AppStore s, String table, Map<String, dynamic> d) {
    switch (table) {
      case 'members':
        final name = _str(d['name']);
        _put<Member>(
          s.members,
          Member(
            id: d['id'] as String, name: name, initial: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), age: _int(d['age']),
            bloodGroup: _str(d['bloodGroup']), sex: Sex.values.byName(d['sex'] as String), role: Role.values.byName((d['role'] as String?) ?? 'full'),
            color: _color(d['color']), conditions: List<String>.from(d['conditions'] as List? ?? []), heightCm: (d['heightCm'] as num?)?.toDouble(),
            abha: _str(d['abha']), insurance: _str(d['insurance']), allergies: _str(d['allergies']), familyHistory: _str(d['familyHistory']), fullName: _str(d['fullName']),
            contacts: (d['contacts'] as List? ?? []).map((e) => Contact.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
          ),
          (m) => m.id == d['id'],
        );
      case 'documents':
        final old = s.doc(d['id'] as String);
        final status = switch (d['status']) { 'needs_review' => DocStatus.needsReview, 'failed' => DocStatus.failed, _ => DocStatus.parsed };
        _put<Doc>(
          s.docs,
          Doc(
            id: d['id'] as String, memberId: d['memberId'] as String, lab: _str(d['lab']), date: _day(d['date']),
            kind: DocKind.values.byName((d['kind'] as String?) ?? 'lab'), status: status, testCount: _int(d['testCount']), pages: _int(d['pages'], 1),
            note: _str(d['note']), filePath: old?.filePath, isImage: old?.isImage ?? ((d['mimeType'] as String?)?.startsWith('image/') ?? false), failedPage: old?.failedPage,
          ),
          (x) => x.id == d['id'],
        );
      case 'labResults':
        final lab = LabResult(
            id: d['id'] as String, memberId: d['memberId'] as String, testKey: d['testKey'] as String, value: _dbl(d['value']), unit: _str(d['unit']),
            date: _day(d['date']), docId: d['docId'] as String, lab: _str(d['lab']), rawName: _str(d['rawName']), confidence: _dbl(d['confidence'], 1),
            confirmed: d['confirmed'] as bool? ?? true, checkNote: _str(d['checkNote']), refText: _str(d['refText']),
        );
        normalizeLab(lab); // e.g. a T3 still stored in ng/dL by an older phone
        _put<LabResult>(s.labs, lab, (x) => x.id == d['id']);
      case 'medicines':
        final old = s.medicine(d['id'] as String);
        final created = d['createdAt'] == null ? null : _local(d['createdAt']);
        final start = (created != null && dayKey(created) == d['startDate']) ? created : _day(d['startDate']);
        _put<Medicine>(
          s.meds,
          Medicine(
            id: d['id'] as String, memberId: d['memberId'] as String, name: _str(d['name']), strength: _str(d['strength']),
            food: Food.values.byName((d['food'] as String?) ?? 'after'),
            times: (d['times'] as List? ?? []).map((e) => DoseTime.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
            stock: _dbl(d['stock']), startDate: start, refillDays: _int(d['refillDays'], 7), photoPath: old?.photoPath, tablets: _dbl(d['tablets'], 1),
            active: d['active'] as bool? ?? true, forCondition: _str(d['forCondition']), teluguName: old?.teluguName ?? '',
          ),
          (x) => x.id == d['id'],
        );
      case 'doseLogs':
        final l = DoseLog(
          medId: d['medId'] as String, memberId: d['memberId'] as String, day: d['day'] as String, timeKey: d['timeKey'] as String,
          state: DoseState.values.byName(d['state'] as String), at: _local(d['at']),
        );
        s.logs[l.key] = l;
      case 'vitals':
        _put<Vital>(
          s.vitals,
          Vital(id: d['id'] as String, memberId: d['memberId'] as String, type: VitalType.values.byName(d['type'] as String), at: _local(d['at']), a: _dbl(d['a']), b: _dbl(d['b']), pulse: _dbl(d['pulse']), afterMeal: d['afterMeal'] as bool? ?? false),
          (x) => x.id == d['id'],
        );
      case 'appointments':
        _put<Appointment>(
          s.appts,
          Appointment(
            id: d['id'] as String, memberId: d['memberId'] as String, title: _str(d['title']), place: _str(d['place']), at: _local(d['at']),
            reason: _str(d['reason']), notes: _str(d['notes']), takeDocId: d['takeDocId'] as String?, prescriptionDocId: d['prescriptionDocId'] as String?,
          ),
          (x) => x.id == d['id'],
        );
      case 'checkups':
        _put<Checkup>(
          s.checkups,
          Checkup(id: d['id'] as String, memberId: d['memberId'] as String, name: _str(d['name']), intervalMonths: _int(d['intervalMonths'], 12), last: d['last'] == null ? null : _day(d['last']), condition: _str(d['condition'])),
          (x) => x.id == d['id'],
        );
    }
  }
}

class LocalRecord {
  LocalRecord(this.table, this.id, this.data, this.memberId, this.parent);
  final String table, id;
  final Map<String, dynamic> data;
  final String? memberId, parent;
}
