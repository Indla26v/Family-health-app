import 'dart:convert';

import 'package:family_health/data/models.dart';
import 'package:family_health/data/store.dart';
import 'package:family_health/services/api_client.dart';
import 'package:family_health/services/sync_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny in-memory stand-in for the web app's auth + sync API.
class FakeServer {
  final rows = <String, Map<String, dynamic>>{}; // table|id → {data, updatedAt, rev}
  final deletes = <Map<String, dynamic>>[];
  var rev = 0;
  var accessOk = true;
  final pushes = <List<dynamic>>[];

  /// Table whose upserts are refused (as the real server does for invalid data).
  String? refuseTable;

  void serverUpsert(String table, String id, Map<String, dynamic> data, DateTime at) {
    rows['$table|$id'] = {'table': table, 'id': id, 'data': data, 'updatedAt': at.toUtc().toIso8601String(), 'rev': ++rev};
  }

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    http.Response js(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    if (path == '/api/auth/login') {
      return js({'accessToken': 'a1', 'refreshToken': 'r1', 'user': {'id': 'u1', 'email': 'mom@x.test', 'familyId': 'fam1', 'access': 'member', 'memberId': null}});
    }
    if (path == '/api/auth/refresh') {
      accessOk = true;
      return js({'accessToken': 'a2', 'refreshToken': 'r2', 'user': {'id': 'u1', 'email': 'mom@x.test', 'familyId': 'fam1', 'access': 'member'}});
    }
    if (!accessOk || r.headers['authorization'] == null) return js({'error': 'Not signed in'}, 401);
    if (path == '/api/auth/me') return js({'user': {'id': 'u1', 'email': 'mom@x.test', 'familyId': 'fam1', 'access': 'member'}});
    if (path == '/api/v1/sync' && r.method == 'GET') {
      final since = int.parse(r.url.queryParameters['since'] ?? '0');
      final changes = [
        for (final row in rows.values)
          if ((row['rev'] as int) > since) {'table': row['table'], 'op': 'upsert', 'id': row['id'], 'rev': row['rev'], 'updatedAt': row['updatedAt'], 'data': row['data']},
        for (final d in deletes)
          if ((d['rev'] as int) > since) d,
      ]..sort((a, b) => (a['rev'] as int).compareTo(b['rev'] as int));
      return js({'changes': changes, 'cursor': changes.isEmpty ? since : changes.last['rev'], 'hasMore': false});
    }
    if (path == '/api/v1/sync' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final changes = body['changes'] as List;
      pushes.add(changes);
      final applied = <Map<String, dynamic>>[], conflicts = <Map<String, dynamic>>[];
      for (final c in changes.cast<Map<String, dynamic>>()) {
        final k = '${c['table']}|${c['id']}';
        final at = DateTime.parse(c['updatedAt'] as String);
        final ex = rows[k];
        if (c['table'] == refuseTable) {
          conflicts.add({'table': c['table'], 'id': c['id'], 'reason': 'invalid: heightCm', 'server': null});
          continue;
        }
        if (ex != null && DateTime.parse(ex['updatedAt'] as String).isAfter(at)) {
          conflicts.add({'table': c['table'], 'id': c['id'], 'reason': 'stale', 'server': ex['data'], 'updatedAt': ex['updatedAt']});
          continue;
        }
        if (c['op'] == 'delete') {
          rows.remove(k);
          deletes.add({'table': c['table'], 'op': 'delete', 'id': c['id'], 'rev': ++rev, 'deletedAt': at.toUtc().toIso8601String(), 'memberId': null});
        } else {
          serverUpsert(c['table'] as String, c['id'] as String, Map<String, dynamic>.from(c['data'] as Map), at);
        }
        applied.add({'table': c['table'], 'id': c['id']});
      }
      return js({'applied': applied, 'conflicts': conflicts});
    }
    if (path.startsWith('/api/v1/files/')) return js({'error': 'No file stored'}, 404);
    return js({'error': 'not found'}, 404);
  }
}

Member _member(AppStore s, String id, String name) => Member(id: id, name: name, initial: name[0], age: 50, bloodGroup: '', sex: Sex.female, role: Role.full, color: const Color(0xFF14B8A6));

void main() {
  late AppStore store;
  late FakeServer server;
  late SyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    store = await AppStore.load();
    server = FakeServer();
    final tokens = TokenStore.instance;
    tokens
      ..accessToken = null
      ..refreshToken = null
      ..account = null;
    sync = SyncService(store, api: ApiClient(tokens, client: MockClient(server.handle)))..attach();
  });

  tearDown(() => sync.dispose());

  test('old short ids become UUIDs with references kept', () {
    final j = <String, dynamic>{
      'prefs': {'deviceUserId': 'father'},
      'members': [{'id': 'father'}],
      'docs': [{'id': 'd1', 'memberId': 'father'}],
      'labs': [{'id': 'l1', 'memberId': 'father', 'docId': 'd1'}],
      'meds': [{'id': 'm1', 'memberId': 'father'}],
      'logs': [{'m': 'm1', 'p': 'father'}],
      'vitals': <dynamic>[], 'appts': [{'id': 'a1', 'memberId': 'father', 'takeDocId': 'd1', 'prescriptionDocId': null}], 'checkups': <dynamic>[],
    };
    expect(AppStore.migrateIdsToUuid(j), isTrue);
    final fid = (j['members'] as List).first['id'] as String;
    expect(fid.length, 36);
    expect((j['prefs'] as Map)['deviceUserId'], fid);
    expect((j['labs'] as List).first['docId'], (j['docs'] as List).first['id']);
    expect((j['logs'] as List).first['m'], (j['meds'] as List).first['id']);
    expect((j['appts'] as List).first['takeDocId'], (j['docs'] as List).first['id']);
    expect(AppStore.migrateIdsToUuid(j), isFalse);
  });

  test('new records get UUIDs', () {
    expect(store.newId('v').length, 36);
  });

  test('sign in uploads local records, then pulls server changes (last write wins)', () async {
    final local = _member(store, store.newId(), 'Amma');
    store.addMember(local);
    store.saveNow();
    store.prefs.deviceUserAsked = true;
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    expect(sync.signedIn, isTrue);
    expect(store.prefs.deviceUserAsked, isFalse, reason: 'every sign-in asks "who uses this phone?" again');
    expect(server.rows.keys.where((k) => k.startsWith('members|')), contains('members|${local.id}'));
    expect(server.rows.keys.where((k) => k.startsWith('checkups|')), isNotEmpty);
    expect(store.sync.pendingCount, 0);

    // A newer edit made on the web wins over the phone's copy.
    final webData = Map<String, dynamic>.from(server.rows['members|${local.id}']!['data'] as Map)..['name'] = 'Amma (web)';
    server.serverUpsert('members', local.id, webData, DateTime.now().add(const Duration(minutes: 1)));
    await sync.syncNow();
    expect(store.member(local.id)!.name, 'Amma (web)');
    expect(store.sync.pendingCount, 0);

    // A record created on the web arrives on the phone.
    final webId = store.newId();
    server.serverUpsert('members', webId, {...webData, 'id': webId, 'name': 'Nanna'}, DateTime.now());
    await sync.syncNow();
    expect(store.member(webId)?.name, 'Nanna');
  });

  test('local edits are pushed; an older local edit loses to the server copy', () async {
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    final m = _member(store, store.newId(), 'Amma');
    store.addMember(m);
    store.saveNow();
    await sync.syncNow();
    expect(server.rows['members|${m.id}'], isNotNull);

    // Server copy changed "in the future"; the phone edits now → stale → phone adopts server.
    final data = Map<String, dynamic>.from(server.rows['members|${m.id}']!['data'] as Map)..['name'] = 'Server name';
    server.rows['members|${m.id}'] = {...server.rows['members|${m.id}']!, 'data': data, 'updatedAt': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()};
    store.member(m.id)!.name = 'Phone name';
    store.updateMember(store.member(m.id)!);
    store.saveNow();
    await sync.syncNow();
    expect(store.member(m.id)!.name, 'Server name');
  });

  test('a refused record keeps its reason and is sent again on the next full sync', () async {
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    server.refuseTable = 'members';
    final m = _member(store, store.newId(), 'Amma');
    store.addMember(m);
    store.saveNow();
    await sync.syncNow();
    expect(server.rows['members|${m.id}'], isNull);
    expect(store.sync.rejected['members|${m.id}'], 'invalid: heightCm');
    expect(store.sync.pendingCount, 0); // not retried on every quick sync

    server.refuseTable = null; // fixed on the server
    await sync.syncNow(full: true);
    expect(server.rows['members|${m.id}'], isNotNull);
    expect(store.sync.rejected, isEmpty);
  });

  test('records an older app version stopped retrying are recovered', () async {
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    final m = _member(store, store.newId(), 'Amma');
    store.addMember(m);
    store.saveNow();
    // As left by the old app after a refusal: tracked, not dirty, never on the server.
    store.sync.recs['members|${m.id}']!
      ..d = false
      ..s = false;
    await sync.syncNow();
    expect(server.rows['members|${m.id}'], isNull);
    await sync.syncNow(full: true);
    expect(server.rows['members|${m.id}'], isNotNull);
  });

  test('a report without an original online says so instead of failing', () async {
    final d = Doc(id: store.newId(), memberId: store.newId(), lab: 'Lab', date: DateTime(2026, 6, 30), kind: DocKind.lab, status: DocStatus.parsed, testCount: 0);
    expect((await sync.fetchOriginal(d)).$2, 'Sign in to download the original');
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    final (bytes, why) = await sync.fetchOriginal(d);
    expect(bytes, isNull);
    expect(why, 'The original file isn’t stored online');
  });

  test('deletes travel both ways', () async {
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    final m = _member(store, store.newId(), 'Amma');
    store.addMember(m);
    final v = Vital(id: store.newId(), memberId: m.id, type: VitalType.bp, at: DateTime.now(), a: 120, b: 80);
    store.addVital(v);
    store.saveNow();
    await sync.syncNow();
    expect(server.rows['vitals|${v.id}'], isNotNull);

    store.vitals.removeWhere((x) => x.id == v.id);
    store.changed();
    store.saveNow();
    await sync.syncNow();
    expect(server.rows['vitals|${v.id}'], isNull);

    // Deleted on the web → removed on the phone.
    server.rows.remove('members|${m.id}');
    server.deletes.add({'table': 'members', 'op': 'delete', 'id': m.id, 'rev': ++server.rev, 'deletedAt': DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String(), 'memberId': m.id});
    await sync.syncNow();
    expect(store.member(m.id), isNull);
    expect(store.checkupsOf(m.id), isEmpty);
  });

  test('offline: everything keeps working and waits for the next sync', () async {
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    final offlineSync = SyncService(store, api: ApiClient(TokenStore.instance, client: MockClient((_) async => throw http.ClientException('no network'))));
    final m = _member(store, store.newId(), 'Amma');
    store.addMember(m);
    store.saveNow();
    await offlineSync.syncNow();
    expect(offlineSync.offline, isTrue);
    expect(store.member(m.id), isNotNull);
    expect(store.sync.pendingCount, greaterThan(0));
    offlineSync.dispose();
    sync.attach(); // starts a sync in the background; wait for it
    await sync.syncNow();
    while (sync.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(server.rows['members|${m.id}'], isNotNull);
  });

  test('first sign-in folds offline copies into matching online records (no duplicates)', () async {
    // Online: Venkatesh with one report of two values.
    const sv = '11111111-1111-4111-8111-111111111111', sd = '22222222-2222-4222-8222-222222222222';
    final t = DateTime.utc(2026, 10, 10);
    server.serverUpsert('members', sv, {'id': sv, 'name': 'Venkatesh', 'fullName': '', 'age': 21, 'sex': 'male', 'bloodGroup': 'O+', 'color': '#0F766E', 'role': 'admin', 'conditions': <String>[], 'heightCm': null, 'abha': '', 'insurance': '', 'allergies': '', 'familyHistory': '', 'contacts': <dynamic>[]}, t);
    server.serverUpsert('documents', sd, {'id': sd, 'memberId': sv, 'lab': 'Lab report', 'date': '2026-10-10', 'kind': 'lab', 'status': 'parsed', 'testCount': 2, 'pages': 1, 'note': '', 'fileName': 'r.pdf', 'mimeType': 'application/pdf'}, t);
    for (final (id, k, v) in [('33333333-3333-4333-8333-333333333333', 'hb', 14.3), ('44444444-4444-4444-8444-444444444444', 'tsh', 2.25)]) {
      server.serverUpsert('labResults', id, {'id': id, 'memberId': sv, 'docId': sd, 'testKey': k, 'value': v, 'unit': '', 'date': '2026-10-10', 'lab': 'Lab report', 'rawName': '', 'confidence': 1, 'confirmed': true, 'checkNote': '', 'refText': ''}, t);
    }

    // This phone, used offline: its own Venkatesh with the same report, plus Anitha with a reading.
    final me = Member(id: store.newId(), name: 'venkatesh ', initial: 'V', age: 21, bloodGroup: 'O+', sex: Sex.male, role: Role.admin, color: const Color(0xFF0F766E));
    final anitha = _member(store, store.newId(), 'Anitha');
    store.addMember(me);
    store.addMember(anitha);
    store.prefs.deviceUserId = me.id;
    final d = Doc(id: store.newId(), memberId: me.id, lab: 'Lab report', date: DateTime(2026, 10, 10), kind: DocKind.lab, status: DocStatus.parsed, testCount: 2, filePath: '/files/r.pdf');
    store.addDoc(d, [
      LabResult(id: store.newId(), memberId: me.id, testKey: 'hb', value: 14.3, unit: 'g/dL', date: d.date, docId: d.id, lab: d.lab),
      LabResult(id: store.newId(), memberId: me.id, testKey: 'tsh', value: 2.25, unit: 'µIU/mL', date: d.date, docId: d.id, lab: d.lab),
    ]);
    store.addVital(Vital(id: store.newId(), memberId: anitha.id, type: VitalType.bp, at: DateTime.now(), a: 120, b: 80));
    store.saveNow();

    await sync.signIn('https://example.test', 'mom@x.test', 'pw');

    List<Map<String, dynamic>> onServer(String table) => server.rows.values.where((r) => r['table'] == table).map((r) => r['data'] as Map<String, dynamic>).toList();
    expect(onServer('members').map((m) => m['name']), unorderedEquals(['Venkatesh', 'Anitha']));
    expect(onServer('documents').map((x) => x['id']), [sd]);
    expect(onServer('labResults'), hasLength(2));
    expect(onServer('vitals').single['memberId'], anitha.id);
    // Phone: the online Venkatesh replaces the local one, keeps the file and stays "who uses this phone".
    expect(store.members.map((m) => m.id), unorderedEquals([sv, anitha.id]));
    expect(store.prefs.deviceUserId, sv);
    expect(store.doc(sd)?.filePath, '/files/r.pdf');
    expect(store.docs, hasLength(1));
    expect(store.sync.pendingCount, 0);
  });

  test('expired access token is refreshed automatically', () async {
    await sync.signIn('https://example.test', 'mom@x.test', 'pw');
    server.accessOk = false; // next call answers 401 until refreshed
    await sync.syncNow();
    expect(sync.needsSignIn, isFalse);
    expect(TokenStore.instance.refreshToken, 'r2');
  });

  test('password is never sent to a plain-http or malformed server address', () async {
    final sent = <Uri>[];
    final api = ApiClient(TokenStore.instance, client: MockClient((r) async {
      sent.add(r.url);
      return server.handle(r);
    }));
    for (final bad in ['http://example.test', 'http://192.168.1.5:3000', 'ftp://example.test', 'https://user:pw@example.test', 'https://example.test/?next=x', 'example.test']) {
      await expectLater(api.login(bad, 'mom@x.test', 'pw'), throwsA(isA<ApiException>()), reason: bad);
    }
    expect(sent, isEmpty);
    expect(ApiClient.checkServerUrl(' https://example.test// '), 'https://example.test');
    expect(ApiClient.checkServerUrl('http://localhost:3000'), 'http://localhost:3000');
    expect(ApiClient.checkServerUrl('http://10.0.2.2:3000/'), 'http://10.0.2.2:3000');
    await api.login('https://example.test', 'mom@x.test', 'pw');
    expect(sent.single.toString(), 'https://example.test/api/auth/login');
  });
}
