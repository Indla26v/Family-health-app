import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Web app the phone syncs with. Override at build time with
/// `flutter run --dart-define=API_BASE_URL=https://your-app.vercel.app`.
const kDefaultApiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://family-health-web-hazel.vercel.app');

/// The signed-in account as the server describes it (`/api/auth/me`).
class AccountInfo {
  AccountInfo({required this.userId, required this.email, required this.familyId, required this.access, this.memberId, this.memberName, this.healthOrder});
  final String userId, email, familyId, access;
  final String? memberId, memberName;

  /// The user's Health card order as the server has it (null from older servers).
  final List<String>? healthOrder;

  /// owner/admin/member may change records; viewer is read-only.
  bool get canWrite => access != 'viewer';
  bool get isAdmin => access == 'owner' || access == 'admin';
  bool get isOwner => access == 'owner';

  Map<String, dynamic> toJson() => {'userId': userId, 'email': email, 'familyId': familyId, 'access': access, 'memberId': memberId, 'memberName': memberName};
  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        userId: j['userId'] as String,
        email: (j['email'] ?? '') as String,
        familyId: j['familyId'] as String,
        access: (j['access'] ?? 'viewer') as String,
        memberId: j['memberId'] as String?,
        memberName: j['memberName'] as String?,
      );
  factory AccountInfo.fromServer(Map<String, dynamic> u) => AccountInfo(
        userId: u['id'] as String,
        email: (u['email'] ?? u['username'] ?? '') as String,
        familyId: u['familyId'] as String,
        access: (u['access'] ?? 'viewer') as String,
        memberId: u['memberId'] as String?,
        memberName: u['memberName'] as String?,
        healthOrder: (u['healthOrder'] as List?)?.cast<String>(),
      );
}

/// Tokens live in the platform keystore (Android Keystore / iOS Keychain /
/// Windows Credential Manager) via flutter_secure_storage — never in the JSON
/// data file. They're cached in memory after [load].
class TokenStore {
  TokenStore._();
  static final instance = TokenStore._();

  static const _storage = FlutterSecureStorage();
  static const _kBase = 'fh_api_base', _kAccess = 'fh_access_token', _kRefresh = 'fh_refresh_token', _kAccount = 'fh_account';

  String baseUrl = kDefaultApiBase;
  String? accessToken, refreshToken;
  AccountInfo? account;

  /// The last signed-in account is kept even when its tokens stop working, so the
  /// app keeps working offline; sync resumes after signing in again.
  bool get hasAccount => account != null;
  bool get hasRefresh => refreshToken != null && refreshToken!.isNotEmpty;

  Future<void> load() async {
    try {
      baseUrl = await _storage.read(key: _kBase) ?? kDefaultApiBase;
      accessToken = await _storage.read(key: _kAccess);
      refreshToken = await _storage.read(key: _kRefresh);
      final a = await _storage.read(key: _kAccount);
      account = a == null ? null : AccountInfo.fromJson(jsonDecode(a) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Secure storage unavailable: $e');
    }
  }

  Future<void> save({String? base, String? access, String? refresh, AccountInfo? acct}) async {
    if (base != null) baseUrl = base;
    if (access != null) accessToken = access;
    if (refresh != null) refreshToken = refresh;
    if (acct != null) account = acct;
    try {
      await _storage.write(key: _kBase, value: baseUrl);
      if (accessToken != null) await _storage.write(key: _kAccess, value: accessToken);
      if (refreshToken != null) await _storage.write(key: _kRefresh, value: refreshToken);
      if (account != null) await _storage.write(key: _kAccount, value: jsonEncode(account!.toJson()));
    } catch (e) {
      debugPrint('Could not save tokens: $e');
    }
  }

  /// Tokens no longer valid (expired or revoked): keep the account for offline use.
  Future<void> dropTokens() async {
    accessToken = null;
    refreshToken = null;
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {}
  }

  /// Explicit sign-out: forget everything about the account on this phone.
  Future<void> clear() async {
    await dropTokens();
    account = null;
    try {
      await _storage.delete(key: _kAccount);
    } catch (_) {}
  }
}

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiException($status): $message';
}

/// No network / server unreachable: the app just keeps working offline.
class OfflineException implements Exception {
  OfflineException(this.cause);
  final Object cause;
  @override
  String toString() => 'Offline: $cause';
}

/// Session can't be refreshed any more; the person must sign in again to sync.
class SessionExpiredException implements Exception {}

/// Small REST client for the web app: Bearer access token on every call, and one
/// automatic refresh (rotating refresh token) when the server answers 401.
class ApiClient {
  ApiClient(this.tokens, {http.Client? client}) : _http = client ?? http.Client();
  final TokenStore tokens;
  final http.Client _http;
  Future<bool>? _refreshing;
  static const _timeout = Duration(seconds: 25);

  Uri _uri(String path, [String? base]) => Uri.parse('${(base ?? tokens.baseUrl).replaceAll(RegExp(r'/+$'), '')}$path');

  static Map<String, dynamic> _json(http.Response r) {
    if (r.body.isEmpty) return {};
    try {
      final v = jsonDecode(r.body);
      return v is Map<String, dynamic> ? v : {'data': v};
    } catch (_) {
      return {'error': r.body.length > 200 ? r.body.substring(0, 200) : r.body};
    }
  }

  Future<http.Response> _raw(Future<http.Response> Function() f) async {
    try {
      return await f().timeout(_timeout);
    } on TimeoutException catch (e) {
      throw OfflineException(e);
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    } catch (e) {
      // SocketException/HandshakeException etc. (dart:io types aren't available on web)
      if (e is ApiException) rethrow;
      throw OfflineException(e);
    }
  }

  /// Hosts that may use plain http: this device and the Android emulator's host (development only).
  static const _localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};

  /// The server address without trailing slashes. The password and tokens travel to it, so it
  /// must be https (http only for [_localHosts]); throws [ApiException] (status 0) otherwise.
  static String checkServerUrl(String base) {
    final u = Uri.tryParse(base.trim());
    if (u == null || u.host.isEmpty || u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment || !(u.scheme == 'https' || u.scheme == 'http')) {
      throw ApiException(0, 'Enter the server address, like https://your-app.vercel.app');
    }
    if (u.scheme == 'http' && !_localHosts.contains(u.host)) throw ApiException(0, 'The server address must start with https://');
    return base.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// POST /api/auth/login → stores tokens and the account. Throws [ApiException] with a
  /// generic message on wrong credentials.
  Future<AccountInfo> login(String base, String email, String password) async {
    base = checkServerUrl(base);
    final r = await _raw(() => _http.post(_uri('/api/auth/login', base), headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email.trim(), 'password': password})));
    return _signedIn(base, r, 'Sign-in failed');
  }

  /// POST /api/auth/signup → emails a 6-digit code to [email]. A new account starts its
  /// own family (as owner). Throws [ApiException] with the server's message (weak password…).
  Future<void> signUpStart(String base, String name, String email, String password) async {
    base = checkServerUrl(base);
    final r = await _raw(() => _http.post(_uri('/api/auth/signup', base), headers: {'content-type': 'application/json'}, body: jsonEncode({'name': name.trim(), 'email': email.trim(), 'password': password})));
    if (r.statusCode != 200) throw ApiException(r.statusCode, (_json(r)['error'] ?? 'Sign-up failed') as String);
  }

  /// POST /api/auth/signup/verify → the code creates the account; stores its tokens like [login].
  Future<AccountInfo> signUpVerify(String base, String email, String code) async {
    base = checkServerUrl(base);
    final r = await _raw(() => _http.post(_uri('/api/auth/signup/verify', base), headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email.trim(), 'code': code.trim()})));
    return _signedIn(base, r, 'Sign-up failed');
  }

  /// A login or sign-up answer: stores the tokens and the account.
  Future<AccountInfo> _signedIn(String base, http.Response r, String failed) async {
    final j = _json(r);
    if (r.statusCode != 200 && r.statusCode != 201) throw ApiException(r.statusCode, (j['error'] ?? failed) as String);
    final acct = AccountInfo.fromServer(j['user'] as Map<String, dynamic>);
    await tokens.save(base: base, access: j['accessToken'] as String, refresh: j['refreshToken'] as String, acct: acct);
    return acct;
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share one request.
  Future<bool> refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final f = _doRefresh();
    _refreshing = f;
    unawaited(f.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_refreshing, f)) _refreshing = null;
    }));
    return f;
  }

  Future<bool> _doRefresh() async {
    if (!tokens.hasRefresh) return false;
    final r = await _raw(() => _http.post(_uri('/api/auth/refresh'), headers: {'content-type': 'application/json'}, body: jsonEncode({'refreshToken': tokens.refreshToken})));
    if (r.statusCode == 200) {
      final j = _json(r);
      final user = j['user'];
      await tokens.save(access: j['accessToken'] as String, refresh: j['refreshToken'] as String, acct: user is Map<String, dynamic> ? AccountInfo.fromServer(user) : null);
      return true;
    }
    if (r.statusCode == 401) await tokens.dropTokens();
    return false;
  }

  /// Revokes the refresh token on the server (best effort) and forgets the account.
  Future<void> logout() async {
    final rt = tokens.refreshToken;
    if (rt != null) {
      try {
        await _raw(() => _http.post(_uri('/api/auth/logout'), headers: {'content-type': 'application/json'}, body: jsonEncode({'refreshToken': rt})));
      } catch (_) {}
    }
    await tokens.clear();
  }

  /// Authenticated request; refreshes once on 401.
  Future<http.Response> send(String method, String path, {Object? json, List<int>? bytes, Map<String, String>? headers}) async {
    Future<http.Response> go() {
      final req = http.Request(method, _uri(path));
      if (tokens.accessToken != null) req.headers['authorization'] = 'Bearer ${tokens.accessToken}';
      if (headers != null) req.headers.addAll(headers);
      if (json != null) {
        req.headers['content-type'] = 'application/json';
        req.body = jsonEncode(json);
      } else if (bytes != null) {
        req.bodyBytes = bytes;
      }
      return _raw(() async => http.Response.fromStream(await _http.send(req)));
    }

    if (tokens.accessToken == null && !(await refresh())) throw SessionExpiredException();
    var r = await go();
    if (r.statusCode == 401) {
      if (!(await refresh())) throw SessionExpiredException();
      r = await go();
      if (r.statusCode == 401) throw SessionExpiredException();
    }
    return r;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final r = await send('GET', path);
    final j = _json(r);
    if (r.statusCode >= 400) throw ApiException(r.statusCode, (j['error'] ?? 'Request failed') as String);
    return j;
  }

  Future<Map<String, dynamic>> postJson(String path, Object body) async {
    final r = await send('POST', path, json: body);
    final j = _json(r);
    if (r.statusCode >= 400) throw ApiException(r.statusCode, (j['error'] ?? 'Request failed') as String);
    return j;
  }

  /// PATCH /api/auth/me → saves this user's Health card order on the account.
  Future<void> saveHealthOrder(List<String> order) async {
    final r = await send('PATCH', '/api/auth/me', json: {'healthOrder': order});
    if (r.statusCode >= 400) throw ApiException(r.statusCode, 'Could not save the card order');
  }

  /// POST /api/v1/confirm-code → emails the owner a 6-digit code before "Delete everything".
  /// Returns the masked address it went to ("ve•••@gmail.com").
  Future<String> requestDeleteCode() async {
    final j = await postJson('/api/v1/confirm-code', {'purpose': 'delete-family'});
    return (j['sentTo'] ?? 'your email') as String;
  }

  /// POST /api/v1/family/delete-everything → with the emailed code: the server saves a
  /// compressed backup in the cloud (6 months), then deletes the family's records everywhere.
  Future<void> deleteEverything(String code) => postJson('/api/v1/family/delete-everything', {'code': code.trim()});

  /// GET /api/v1/backups → the backup waiting for "Restore or start new?" (owner only), or null.
  Future<Map<String, dynamic>?> pendingBackup() async => (await getJson('/api/v1/backups'))['pending'] as Map<String, dynamic>?;

  /// POST /api/v1/backups/:id/restore → puts the family's records back on the server.
  Future<void> restoreBackup(String id) => postJson('/api/v1/backups/$id/restore', const {});

  /// POST /api/v1/backups/:id/start-new → keeps the family empty (the backup stays 6 months).
  Future<void> startNew(String id) => postJson('/api/v1/backups/$id/start-new', const {});

  /// GET /api/auth/me → refreshes the cached account (role changes, profile link).
  Future<AccountInfo> me() async {
    final j = await getJson('/api/auth/me');
    final acct = AccountInfo.fromServer(j['user'] as Map<String, dynamic>);
    await tokens.save(acct: acct);
    return acct;
  }
}
