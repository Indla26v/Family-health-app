import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/strings.dart';
import 'catalog.dart';
import 'models.dart';
import 'sync_state.dart';

// v1 held the design's sample family; it is discarded so the app starts clean.
const _kKey = 'family_health_v2';
const _kOldKeys = ['family_health_v1'];

/// Single source of truth. Everything is kept on the phone (offline-first) as
/// one JSON document; there is deliberately no network dependency here. Cloud
/// sync (services/sync_service.dart) works on top of this: it watches saves via
/// [beforeSave] and keeps its bookkeeping in [sync].
class AppStore extends ChangeNotifier {
  AppStore._(this._sp);
  final SharedPreferences _sp;
  Timer? _saveTimer;
  static const _uuid = Uuid();

  /// Sync bookkeeping (per-record dirty flags, tombstones, cursor). Saved with the data.
  SyncState sync = SyncState();

  /// Called right before every save (the sync service records what changed).
  void Function()? beforeSave;

  /// Called after every save (the sync service schedules a push).
  void Function()? afterSave;

  Prefs prefs = Prefs();
  List<Member> members = [];
  List<Doc> docs = [];
  List<LabResult> labs = [];
  List<Medicine> meds = [];
  final Map<String, DoseLog> logs = {};
  List<Vital> vitals = [];
  List<Appointment> appts = [];
  List<Checkup> checkups = [];
  ImportJob? job;

  /// Member filter on Today / Medicines / Health (null = everyone).
  String? selectedId;

  /// True once the user has unlocked this session.
  bool unlocked = false;

  /// A parent on simple mode can open the full app for this session.

  static Future<AppStore> load() async {
    final s = AppStore._(await SharedPreferences.getInstance());
    for (final k in _kOldKeys) {
      await s._sp.remove(k);
    }
    final raw = s._sp.getString(_kKey);
    if (raw != null) {
      try {
        s._fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Could not read saved data, starting fresh: $e');
        s._resetAll();
      }
    }
    Lang.code = s.prefs.lang;
    return s;
  }

  // ---------------------------------------------------------------- persistence
  void _resetAll() {
    prefs = Prefs();
    members = [];
    docs = [];
    labs = [];
    meds = [];
    logs.clear();
    vitals = [];
    appts = [];
    checkups = [];
    job = null;
    sync.reset();
  }

  void _fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        (j[k] as List? ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    prefs = Prefs.fromJson(Map<String, dynamic>.from(j['prefs'] ?? {}));
    members = list('members', Member.fromJson);
    docs = list('docs', Doc.fromJson);
    labs = list('labs', LabResult.fromJson);
    for (final l in labs) {
      normalizeLab(l);
    }
    meds = list('meds', Medicine.fromJson);
    vitals = list('vitals', Vital.fromJson);
    appts = list('appts', Appointment.fromJson);
    checkups = list('checkups', Checkup.fromJson);
    logs.clear();
    for (final l in list('logs', DoseLog.fromJson)) {
      logs[l.key] = l;
    }
    job = j['job'] == null ? null : ImportJob.fromJson(Map<String, dynamic>.from(j['job']));
    sync = SyncState.fromJson(j['sync'] == null ? null : Map<String, dynamic>.from(j['sync'] as Map));
  }

  Map<String, dynamic> toJson() => {
        'prefs': prefs.toJson(),
        'members': members.map((e) => e.toJson()).toList(),
        'docs': docs.map((e) => e.toJson()).toList(),
        'labs': labs.map((e) => e.toJson()).toList(),
        'meds': meds.map((e) => e.toJson()).toList(),
        'logs': logs.values.map((e) => e.toJson()).toList(),
        'vitals': vitals.map((e) => e.toJson()).toList(),
        'appts': appts.map((e) => e.toJson()).toList(),
        'checkups': checkups.map((e) => e.toJson()).toList(),
        'job': job?.toJson(),
        'sync': sync.toJson(),
      };

  void _saveNow() {
    _saveTimer?.cancel();
    try {
      beforeSave?.call();
    } catch (e) {
      debugPrint('Sync tracking failed: $e');
    }
    _sp.setString(_kKey, jsonEncode(toJson()));
    afterSave?.call();
  }

  /// Saves immediately (used by sync before and after talking to the server).
  void saveNow() => _saveNow();

  /// Repaints listeners without saving (sync status changes).
  void refresh() => notifyListeners();

  /// Call after every mutation: notifies listeners and writes to disk (debounced).
  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveNow);
  }

  /// New record id. UUIDs, so records created offline on any device never collide
  /// and the server can store them as they are. (The prefix argument is ignored.)
  String newId([String p = 'x']) => _uuid.v4();

  static final _uuidRe = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  /// Before the first cloud sync: records created by older versions used short local
  /// ids; the server needs UUIDs. Returns true if anything was renamed.
  bool migrateIdsNow() {
    final j = toJson();
    if (!migrateIdsToUuid(j)) return false;
    final keepSync = sync;
    _fromJson(j);
    sync = keepSync;
    selectedId = null;
    changed();
    return true;
  }

  /// Rewrites non-UUID ids (from before cloud sync) to UUIDs, including every
  /// reference to them. Works on the saved JSON; returns true if anything changed.
  static bool migrateIdsToUuid(Map<String, dynamic> j) {
    final map = <String, String>{};
    String fix(String id) => _uuidRe.hasMatch(id) ? id : map.putIfAbsent(id, () => _uuid.v4());
    var changed = false;
    void each(String key, void Function(Map<String, dynamic> e) f) {
      for (final e in (j[key] as List? ?? [])) {
        f(e as Map<String, dynamic>);
      }
    }

    // First pass: assign new ids to every record.
    for (final key in ['members', 'docs', 'labs', 'meds', 'vitals', 'appts', 'checkups']) {
      each(key, (e) {
        final id = e['id'] as String;
        if (!_uuidRe.hasMatch(id)) {
          e['id'] = fix(id);
          changed = true;
        }
      });
    }
    if (!changed) return false;
    // Second pass: references.
    String? ref(Object? id) => id == null ? null : (map[id as String] ?? id);
    for (final key in ['docs', 'labs', 'meds', 'vitals', 'appts', 'checkups']) {
      each(key, (e) => e['memberId'] = ref(e['memberId']));
    }
    each('labs', (e) => e['docId'] = ref(e['docId']));
    each('appts', (e) {
      e['takeDocId'] = ref(e['takeDocId']);
      e['prescriptionDocId'] = ref(e['prescriptionDocId']);
    });
    each('logs', (e) {
      e['m'] = ref(e['m']);
      e['p'] = ref(e['p']);
    });
    final prefs = j['prefs'];
    if (prefs is Map<String, dynamic> && prefs['deviceUserId'] is String && (prefs['deviceUserId'] as String).isNotEmpty) {
      prefs['deviceUserId'] = ref(prefs['deviceUserId']);
    }
    return true;
  }

  // ---------------------------------------------------------------- members
  Member? member(String? id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Member get currentUser => member(prefs.deviceUserId) ?? members.first;

  /// First-run setup has been completed (at least one person added).
  bool get isSetUp => prefs.setupDone && members.isNotEmpty;

  /// Distinct, clear colours for people (same as the web app's memberPalette).
  static const _palette = [
    Color(0xFF2563EB), Color(0xFFDB2777), Color(0xFF0D9488), Color(0xFFEA580C),
    Color(0xFF0891B2), Color(0xFFCA8A04), Color(0xFF65A30D), Color(0xFF475569),
  ];

  /// A member colour not yet used by anyone (cycles if the family is large).
  Color nextColor() {
    for (final c in _palette) {
      if (!members.any((m) => m.color.toARGB32() == c.toARGB32())) return c;
    }
    return _palette[members.length % _palette.length];
  }

  void addMember(Member m) {
    members.add(m);
    ensureCheckups(m);
    changed();
  }

  /// Removes a person and everything recorded for them.
  void deleteMember(String id) {
    members.removeWhere((m) => m.id == id);
    docs.removeWhere((d) => d.memberId == id);
    labs.removeWhere((l) => l.memberId == id);
    final medIds = meds.where((m) => m.memberId == id).map((m) => m.id).toSet();
    meds.removeWhere((m) => m.memberId == id);
    logs.removeWhere((k, v) => v.memberId == id || medIds.contains(v.medId));
    vitals.removeWhere((v) => v.memberId == id);
    appts.removeWhere((a) => a.memberId == id);
    checkups.removeWhere((c) => c.memberId == id);
    if (selectedId == id) selectedId = null;
    changed();
  }

  /// Adds the usual check-ups for a person's conditions (never removes any,
  /// so dates already recorded are kept).
  void ensureCheckups(Member m) {
    final want = <(String, int, String)>[
      ('Annual blood test', 12, ''),
      if (m.conditions.contains('diabetes')) ...[('Eye check (retina)', 12, 'diabetes'), ('Kidney check (urine ACR)', 12, 'diabetes'), ('Foot check', 12, 'diabetes')] else ('Eye check', 24, ''),
      if (m.conditions.contains('cholesterol')) ('Lipid profile', 12, 'cholesterol'),
      if (m.conditions.contains('bp')) ('Kidney function test', 12, 'bp'),
      if (m.conditions.contains('thyroid')) ('Thyroid test (TSH)', 12, 'thyroid'),
      if (m.conditions.contains('vitamins')) ('Vitamin D and B12', 12, 'vitamins'),
      if (m.conditions.contains('prostate')) ('PSA test', 12, 'prostate'),
      if (m.conditions.contains('gallbladder')) ('Abdominal ultrasound', 12, 'gallbladder'),
      ('Dental check-up', 12, ''),
    ];
    for (final (name, months, cond) in want) {
      if (checkups.any((c) => c.memberId == m.id && c.name == name)) continue;
      checkups.add(Checkup(id: newId('cu'), memberId: m.id, name: name, intervalMonths: months, condition: cond));
    }
  }
  Member? get admin {
    for (final m in members) {
      if (m.role == Role.admin) return m;
    }
    return null;
  }

  bool get hasData => docs.isNotEmpty || labs.isNotEmpty;

  /// Members whose data the current user may see: everyone has the same access, the whole family.
  List<Member> get visibleMembers => members;

  List<Member> get viewMembers => visibleMembers;

  Member get focusMember => member(selectedId) ?? visibleMembers.first;

  void selectMember(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void updateMember(Member m) => changed();

  // ---------------------------------------------------------------- prefs
  void setLang(String code) {
    prefs.lang = code;
    Lang.code = code;
    changed();
  }

  void setPref(void Function(Prefs p) f) {
    f(prefs);
    changed();
  }

  static String hashPin(String pin) => sha256.convert(utf8.encode('fh-salt:$pin')).toString();
  bool checkPin(String pin) => prefs.pinHash != null && prefs.pinHash == hashPin(pin);
  void setPin(String pin) {
    prefs.pinHash = hashPin(pin);
    changed();
  }

  // ---------------------------------------------------------------- documents & labs
  Doc? doc(String? id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<Doc> docsFor(String? memberId) =>
      (memberId == null ? [...docs] : docs.where((d) => d.memberId == memberId).toList())..sort((a, b) => b.date.compareTo(a.date));

  List<Doc> reviewDocs([String? memberId]) => docsFor(memberId).where((d) => d.status == DocStatus.needsReview).toList();
  int get reviewCount => reviewDocs(null).where((d) => visibleMembers.any((m) => m.id == d.memberId)).length;
  int get processingCount => docs.where((d) => d.status == DocStatus.processing).length;

  List<LabResult> resultsOf(String memberId, String testKey) =>
      labs.where((l) => l.memberId == memberId && l.testKey == testKey && l.confirmed).toList()..sort((a, b) => a.date.compareTo(b.date));

  LabResult? latestResult(String memberId, String testKey) {
    final r = resultsOf(memberId, testKey);
    return r.isEmpty ? null : r.last;
  }

  List<LabResult> labsOfDoc(String docId) => labs.where((l) => l.docId == docId).toList();

  void addDoc(Doc d, [List<LabResult> results = const []]) {
    docs.add(d);
    labs.addAll(results);
    changed();
  }

  /// Marks every pending value of a document as confirmed (after review).
  void confirmDoc(String docId) {
    final d = doc(docId);
    if (d == null) return;
    var n = 0;
    for (final l in labs.where((l) => l.docId == docId)) {
      l.confirmed = true;
      n++;
    }
    d.status = DocStatus.parsed;
    d.testCount = n == 0 ? d.testCount : n;
    changed();
  }

  void removeResult(String id) {
    labs.removeWhere((l) => l.id == id);
    changed();
  }

  void deleteDoc(String id) {
    docs.removeWhere((d) => d.id == id);
    labs.removeWhere((l) => l.docId == id);
    changed();
  }

  // ---------------------------------------------------------------- medicines & doses
  Medicine? medicine(String id) {
    for (final m in meds) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<Medicine> medsOf(String memberId) => meds.where((m) => m.memberId == memberId && m.active).toList();

  static const _grace = Duration(minutes: 90);

  List<Dose> dosesOn(DateTime day, {String? memberId, DateTime? now}) {
    now ??= DateTime.now();
    final d0 = dayOnly(day);
    final out = <Dose>[];
    for (final m in meds) {
      if (!m.active) continue;
      if (memberId != null && m.memberId != memberId) continue;
      if (dayOnly(m.startDate).isAfter(d0)) continue;
      for (final t in m.times) {
        final at = DateTime(d0.year, d0.month, d0.day, t.hour, t.minute);
        // Doses scheduled before the medicine was added don't count.
        if (at.add(_grace).isBefore(m.startDate)) continue;
        final log = logs['${m.id}|${dayKey(d0)}|${t.key}'];
        DoseStatus st;
        if (log != null) {
          st = log.state == DoseState.taken ? DoseStatus.taken : DoseStatus.skipped;
        } else if (d0.isBefore(dayOnly(now))) {
          st = DoseStatus.missed;
        } else if (d0.isAfter(dayOnly(now))) {
          st = DoseStatus.upcoming;
        } else if (now.isAfter(at.add(_grace))) {
          st = DoseStatus.missed;
        } else if (!now.isBefore(at.subtract(const Duration(minutes: 15)))) {
          st = DoseStatus.due;
        } else {
          st = DoseStatus.upcoming;
        }
        out.add(Dose(m, at, st, t));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// The dose to show as "next": something due now, else the next upcoming today,
  /// else the first dose tomorrow.
  Dose? nextDose(String memberId) {
    final now = DateTime.now();
    final today = dosesOn(now, memberId: memberId, now: now);
    for (final d in today) {
      if (d.status == DoseStatus.due) return d;
    }
    for (final d in today) {
      if (d.status == DoseStatus.upcoming) return d;
    }
    final tomorrow = dosesOn(now.add(const Duration(days: 1)), memberId: memberId, now: now);
    return tomorrow.isEmpty ? null : tomorrow.first;
  }

  void _setLog(Dose d, DoseState s) {
    final day = dayKey(d.time);
    final log = DoseLog(medId: d.med.id, memberId: d.med.memberId, day: day, timeKey: d.slot.key, state: s, at: DateTime.now());
    final had = logs[log.key];
    logs[log.key] = log;
    if (s == DoseState.taken && had?.state != DoseState.taken) {
      d.med.stock = max(0, d.med.stock - d.med.tablets);
    } else if (s != DoseState.taken && had?.state == DoseState.taken) {
      d.med.stock += d.med.tablets;
    }
    changed();
  }

  void takeDose(Dose d) => _setLog(d, DoseState.taken);
  void skipDose(Dose d) => _setLog(d, DoseState.skipped);

  void undoDose(Dose d) {
    final k = '${d.med.id}|${dayKey(d.time)}|${d.slot.key}';
    final had = logs.remove(k);
    if (had?.state == DoseState.taken) d.med.stock += d.med.tablets;
    changed();
  }

  /// Whole days of tablets left at the current schedule.
  double daysLeft(Medicine m) {
    final perDay = m.times.length * m.tablets;
    return perDay == 0 ? 999 : m.stock / perDay;
  }

  bool needsRefill(Medicine m) => daysLeft(m) <= m.refillDays;

  void saveMedicine(Medicine m, {bool isNew = false}) {
    if (isNew) meds.add(m);
    changed();
  }

  void deleteMedicine(String id) {
    meds.removeWhere((m) => m.id == id);
    logs.removeWhere((k, v) => v.medId == id);
    changed();
  }

  /// Per-day adherence for a month: returns day -> (expected, taken).
  Map<int, (int, int)> adherenceMonth(String memberId, DateTime month, {DateTime? now}) {
    now ??= DateTime.now();
    final out = <int, (int, int)>{};
    final last = DateTime(month.year, month.month + 1, 0).day;
    for (var i = 1; i <= last; i++) {
      final day = DateTime(month.year, month.month, i);
      if (day.isAfter(now)) continue;
      final doses = dosesOn(day, memberId: memberId, now: now).where((d) => d.status != DoseStatus.upcoming && d.status != DoseStatus.due);
      if (doses.isEmpty) continue;
      out[i] = (doses.length, doses.where((d) => d.status == DoseStatus.taken).length);
    }
    return out;
  }

  List<Dose> missedDoses(String memberId, DateTime month, {DateTime? now}) {
    now ??= DateTime.now();
    final last = DateTime(month.year, month.month + 1, 0).day;
    final out = <Dose>[];
    for (var i = last; i >= 1; i--) {
      final day = DateTime(month.year, month.month, i);
      if (day.isAfter(now)) continue;
      out.addAll(dosesOn(day, memberId: memberId, now: now).where((d) => d.status == DoseStatus.missed || d.status == DoseStatus.skipped));
    }
    return out;
  }

  /// Missed doses today, for the admin alert (e.g. "missed 8:00 AM Metformin").
  List<Dose> missedToday([String? memberId]) {
    final now = DateTime.now();
    return dosesOn(now, memberId: memberId, now: now).where((d) => d.status == DoseStatus.missed).toList();
  }

  // ---------------------------------------------------------------- vitals
  List<Vital> vitalsOf(String memberId, VitalType t) => vitals.where((v) => v.memberId == memberId && v.type == t).toList()..sort((a, b) => a.at.compareTo(b.at));

  Vital? latestVital(String memberId, VitalType t, {bool? afterMeal}) {
    final l = vitalsOf(memberId, t).where((v) => afterMeal == null || v.afterMeal == afterMeal).toList();
    return l.isEmpty ? null : l.last;
  }

  void addVital(Vital v) {
    vitals.add(v);
    changed();
  }

  // ---------------------------------------------------------------- appointments & check-ups
  List<Appointment> upcomingAppts([String? memberId]) {
    final now = DateTime.now();
    return appts.where((a) => (memberId == null || a.memberId == memberId) && visibleMembers.any((m) => m.id == a.memberId) && a.at.isAfter(now.subtract(const Duration(hours: 2)))).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  List<Appointment> pastAppts([String? memberId]) {
    final now = DateTime.now();
    return appts.where((a) => (memberId == null || a.memberId == memberId) && visibleMembers.any((m) => m.id == a.memberId) && !a.at.isAfter(now.subtract(const Duration(hours: 2)))).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  void saveAppointment(Appointment a, {bool isNew = false}) {
    if (isNew) appts.add(a);
    changed();
  }

  void deleteAppointment(String id) {
    appts.removeWhere((a) => a.id == id);
    changed();
  }

  List<Checkup> checkupsOf(String memberId) => checkups.where((c) => c.memberId == memberId).toList();

  void markCheckupDone(Checkup c, DateTime date) {
    c.last = date;
    changed();
  }

  // ---------------------------------------------------------------- insights
  /// Plain-language, descriptive summary of a test's history. Never advice.
  String? insightFor(String memberId, String testKey) {
    final t = testByKey(testKey);
    final r = resultsOf(memberId, testKey);
    if (t == null || r.length < 2) return null;
    final first = r.first, last = r.last;
    final years = last.date.difference(first.date).inDays / 365.25;
    const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
    final yr = years.round();
    final span = years >= 1.5 ? 'over ${yr < words.length ? words[yr] : yr} years' : 'since ${_monthYear(first.date)}';
    final dir = last.value < first.value ? 'come down' : last.value > first.value ? 'gone up' : 'stayed level';
    final m = member(memberId);
    final sex = m?.sex ?? Sex.male;
    var s = '${t.name} has $dir from ${fmtVal(t, first.value)} to ${fmtVal(t, last.value)} $span';
    final cmp = t.target ?? t.highFor(sex);
    if (cmp != null) {
      final under = r.reversed.takeWhile((x) => x.value <= cmp).toList();
      if (under.isNotEmpty && under.length < r.length) {
        s += ' and has been under ${fmtVal(t, cmp)} since ${under.last.date.year}';
      } else if (under.length == r.length) {
        s += ' and has stayed under ${fmtVal(t, cmp)}';
      }
    }
    return '$s.';
  }

  String _monthYear(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.year}';
  }

  // ---------------------------------------------------------------- housekeeping
  /// Deletes everything on this phone and returns to first-run setup.
  void deleteEverything() {
    final keep = prefs;
    _resetAll();
    prefs = Prefs(lang: keep.lang, largeText: keep.largeText, darkMode: keep.darkMode);
    selectedId = null;
    unlocked = false;
    changed();
  }

  String exportJson() => const JsonEncoder.withIndent(' ').convert(toJson());
}
