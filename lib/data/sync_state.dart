/// Per-record sync bookkeeping, saved inside the app's JSON document.
///
/// Every synced record has an entry keyed `table|id`:
///  - `h` hash of its server-shaped data when last seen/saved,
///  - `u` last modification time (UTC) — the last-write-wins clock,
///  - `d` dirty: changed on this phone and not yet accepted by the server,
///  - `s` the server has it (so deleting it locally must send a tombstone),
///  - `m`/`p` member id / parent id (report or medicine), used to skip deletes
///    the server will cascade anyway.
class SyncRec {
  SyncRec({required this.h, required this.u, this.d = false, this.s = false, this.m, this.p});
  String h;
  DateTime u;
  bool d, s;
  String? m, p;

  Map<String, dynamic> toJson() => {'h': h, 'u': u.toUtc().toIso8601String(), 'd': d, 's': s, 'm': m, 'p': p};
  factory SyncRec.fromJson(Map<String, dynamic> j) =>
      SyncRec(h: j['h'] as String, u: DateTime.parse(j['u'] as String), d: j['d'] as bool? ?? false, s: j['s'] as bool? ?? false, m: j['m'] as String?, p: j['p'] as String?);
}

/// A local delete waiting to be pushed.
class Tombstone {
  Tombstone({required this.table, required this.id, required this.u, this.m, this.p});
  final String table, id;
  final DateTime u;
  final String? m, p;
  Map<String, dynamic> toJson() => {'t': table, 'i': id, 'u': u.toUtc().toIso8601String(), 'm': m, 'p': p};
  factory Tombstone.fromJson(Map<String, dynamic> j) => Tombstone(table: j['t'] as String, id: j['i'] as String, u: DateTime.parse(j['u'] as String), m: j['m'] as String?, p: j['p'] as String?);
}

class SyncState {
  /// Server change cursor (`rev`) already pulled.
  int cursor = 0;

  /// Family these records were synced with; signing in to another family clears them.
  String? familyId;
  DateTime? lastSync;
  String? lastError;
  final Map<String, SyncRec> recs = {};
  final List<Tombstone> tombs = [];

  /// Report ids whose original file has been uploaded.
  final Set<String> uploadedFiles = {};

  /// 1 once files skipped as too big have been queued again (they are now sent compacted).
  int filesVersion = 0;

  /// Records the server refused (`table|id` → its reason). They are retried on the
  /// next full sync, so a refusal fixed on either side never leaves a record stranded.
  final Map<String, String> rejected = {};

  int get pendingCount => recs.values.where((r) => r.d).length + tombs.length;

  void reset() {
    cursor = 0;
    familyId = null;
    lastSync = null;
    lastError = null;
    recs.clear();
    tombs.clear();
    uploadedFiles.clear();
    rejected.clear();
  }

  Map<String, dynamic> toJson() => {
        'cursor': cursor,
        'familyId': familyId,
        'lastSync': lastSync?.toUtc().toIso8601String(),
        'lastError': lastError,
        'recs': recs.map((k, v) => MapEntry(k, v.toJson())),
        'tombs': tombs.map((t) => t.toJson()).toList(),
        'files': uploadedFiles.toList(),
        'fv': filesVersion,
        'rej': rejected,
      };

  static SyncState fromJson(Map<String, dynamic>? j) {
    final s = SyncState();
    if (j == null) return s;
    s.cursor = (j['cursor'] as num?)?.toInt() ?? 0;
    s.familyId = j['familyId'] as String?;
    s.lastSync = j['lastSync'] == null ? null : DateTime.parse(j['lastSync'] as String);
    s.lastError = j['lastError'] as String?;
    (j['recs'] as Map? ?? {}).forEach((k, v) => s.recs[k as String] = SyncRec.fromJson(Map<String, dynamic>.from(v as Map)));
    for (final t in (j['tombs'] as List? ?? [])) {
      s.tombs.add(Tombstone.fromJson(Map<String, dynamic>.from(t as Map)));
    }
    s.uploadedFiles.addAll((j['files'] as List? ?? []).map((e) => e as String));
    s.filesVersion = (j['fv'] as num?)?.toInt() ?? 0;
    (j['rej'] as Map? ?? {}).forEach((k, v) => s.rejected[k as String] = v as String);
    return s;
  }
}
