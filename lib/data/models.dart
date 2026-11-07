import 'package:flutter/material.dart';

DateTime _d(dynamic v) => DateTime.parse(v as String);
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

enum Role { admin, full, simple }

enum Sex { male, female }

class Contact {
  Contact(this.name, this.relation, this.phone);
  String name, relation, phone;
  Map<String, dynamic> toJson() => {'name': name, 'relation': relation, 'phone': phone};
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(j['name'], j['relation'], j['phone'] ?? '');
}

class Member {
  Member({
    required this.id,
    required this.name,
    required this.initial,
    required this.age,
    required this.bloodGroup,
    required this.sex,
    required this.role,
    required this.color,
    this.conditions = const [],
    this.heightCm,
    this.abha = '',
    this.insurance = '',
    this.allergies = '',
    this.familyHistory = '',
    this.fullName = '',
    this.contacts = const [],
  });

  final String id;
  String name, initial, bloodGroup, abha, insurance, allergies, familyHistory, fullName;
  int age;
  Sex sex;
  Role role;
  Color color;
  List<String> conditions; // condition ids, see conditions.dart
  double? heightCm;
  List<Contact> contacts;

  String get bloodLabel => bloodGroup.isEmpty ? 'blood group not set' : bloodGroup;

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'initial': initial, 'age': age, 'bloodGroup': bloodGroup, 'sex': sex.name,
        'role': role.name, 'color': color.toARGB32(), 'conditions': conditions, 'heightCm': heightCm, 'abha': abha,
        'insurance': insurance, 'allergies': allergies, 'familyHistory': familyHistory, 'fullName': fullName,
        'contacts': contacts.map((e) => e.toJson()).toList(),
      };
  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'], name: j['name'], initial: j['initial'], age: j['age'], bloodGroup: j['bloodGroup'],
        sex: Sex.values.byName(j['sex']), role: Role.values.byName(j['role']), color: Color(j['color'] as int),
        conditions: List<String>.from(j['conditions'] ?? []), heightCm: (j['heightCm'] as num?)?.toDouble(),
        abha: j['abha'] ?? '', insurance: j['insurance'] ?? '', allergies: j['allergies'] ?? '',
        familyHistory: j['familyHistory'] ?? '', fullName: j['fullName'] ?? '',
        contacts: (j['contacts'] as List? ?? []).map((e) => Contact.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

enum DocStatus { parsed, needsReview, failed, processing }

enum DocKind { lab, prescription, other }

class Doc {
  Doc({
    required this.id,
    required this.memberId,
    required this.lab,
    required this.date,
    required this.kind,
    required this.status,
    this.testCount = 0,
    this.filePath,
    this.isImage = false,
    this.note = '',
    this.pages = 1,
    this.failedPage,
  });
  final String id;
  String memberId, lab, note;
  DateTime date;
  DocKind kind;
  DocStatus status;
  int testCount, pages;
  int? failedPage;
  String? filePath; // null for demo data / web
  bool isImage;

  Map<String, dynamic> toJson() => {
        'id': id, 'memberId': memberId, 'lab': lab, 'date': date.toIso8601String(), 'kind': kind.name,
        'status': status.name, 'testCount': testCount, 'filePath': filePath, 'isImage': isImage, 'note': note,
        'pages': pages, 'failedPage': failedPage,
      };
  factory Doc.fromJson(Map<String, dynamic> j) => Doc(
        id: j['id'], memberId: j['memberId'], lab: j['lab'], date: _d(j['date']), kind: DocKind.values.byName(j['kind']),
        status: DocStatus.values.byName(j['status']), testCount: j['testCount'] ?? 0, filePath: j['filePath'],
        isImage: j['isImage'] ?? false, note: j['note'] ?? '', pages: j['pages'] ?? 1, failedPage: j['failedPage'],
      );
}

class LabResult {
  LabResult({
    required this.id,
    required this.memberId,
    required this.testKey,
    required this.value,
    required this.unit,
    required this.date,
    required this.docId,
    required this.lab,
    this.rawName = '',
    this.confidence = 1,
    this.confirmed = true,
    this.checkNote = '',
    this.refText = '',
  });
  final String id;
  String memberId, testKey, unit, docId, lab, rawName, checkNote, refText;
  double value;
  DateTime date;
  double confidence;
  bool confirmed;

  bool get lowConfidence => confidence < 0.8;

  Map<String, dynamic> toJson() => {
        'id': id, 'memberId': memberId, 'testKey': testKey, 'value': value, 'unit': unit, 'date': date.toIso8601String(),
        'docId': docId, 'lab': lab, 'rawName': rawName, 'confidence': confidence, 'confirmed': confirmed,
        'checkNote': checkNote, 'refText': refText,
      };
  factory LabResult.fromJson(Map<String, dynamic> j) => LabResult(
        id: j['id'], memberId: j['memberId'], testKey: j['testKey'], value: (j['value'] as num).toDouble(), unit: j['unit'],
        date: _d(j['date']), docId: j['docId'], lab: j['lab'], rawName: j['rawName'] ?? '', confidence: (j['confidence'] as num?)?.toDouble() ?? 1,
        confirmed: j['confirmed'] ?? true, checkNote: j['checkNote'] ?? '', refText: j['refText'] ?? '',
      );
}

enum Food { before, after, any }

class DoseTime {
  DoseTime(this.slot, this.hour, this.minute);
  String slot; // morning | afternoon | night
  int hour, minute;
  Map<String, dynamic> toJson() => {'slot': slot, 'h': hour, 'm': minute};
  factory DoseTime.fromJson(Map<String, dynamic> j) => DoseTime(j['slot'], j['h'], j['m']);
  String get key => '$hour:$minute';
}

class Medicine {
  Medicine({
    required this.id,
    required this.memberId,
    required this.name,
    required this.strength,
    required this.food,
    required this.times,
    required this.stock,
    required this.startDate,
    this.refillDays = 7,
    this.photoPath,
    this.tablets = 1,
    this.active = true,
    this.forCondition = '',
    this.teluguName = '',
  });
  final String id;
  String memberId, name, strength, forCondition, teluguName;
  Food food;
  List<DoseTime> times;
  double stock;
  int refillDays;
  double tablets;
  DateTime startDate;
  String? photoPath;
  bool active;

  String get label => strength.isEmpty ? name : '$name $strength';

  Map<String, dynamic> toJson() => {
        'id': id, 'memberId': memberId, 'name': name, 'strength': strength, 'food': food.name,
        'times': times.map((e) => e.toJson()).toList(), 'stock': stock, 'startDate': startDate.toIso8601String(),
        'refillDays': refillDays, 'photoPath': photoPath, 'tablets': tablets, 'active': active,
        'forCondition': forCondition, 'teluguName': teluguName,
      };
  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'], memberId: j['memberId'], name: j['name'], strength: j['strength'] ?? '', food: Food.values.byName(j['food']),
        times: (j['times'] as List).map((e) => DoseTime.fromJson(Map<String, dynamic>.from(e))).toList(),
        stock: (j['stock'] as num).toDouble(), startDate: _d(j['startDate']), refillDays: j['refillDays'] ?? 7,
        photoPath: j['photoPath'], tablets: (j['tablets'] as num?)?.toDouble() ?? 1, active: j['active'] ?? true,
        forCondition: j['forCondition'] ?? '', teluguName: j['teluguName'] ?? '',
      );
}

enum DoseState { taken, skipped }

class DoseLog {
  DoseLog({required this.medId, required this.memberId, required this.day, required this.timeKey, required this.state, required this.at});
  String medId, memberId, day, timeKey; // day = yyyy-MM-dd, timeKey = h:m
  DoseState state;
  DateTime at;
  String get key => '$medId|$day|$timeKey';
  Map<String, dynamic> toJson() => {'m': medId, 'p': memberId, 'd': day, 't': timeKey, 's': state.name, 'a': at.toIso8601String()};
  factory DoseLog.fromJson(Map<String, dynamic> j) =>
      DoseLog(medId: j['m'], memberId: j['p'], day: j['d'], timeKey: j['t'], state: DoseState.values.byName(j['s']), at: _d(j['a']));
}

/// A scheduled dose on a given day, with its derived state.
enum DoseStatus { due, upcoming, taken, skipped, missed }

class Dose {
  Dose(this.med, this.time, this.status, this.slot);
  final Medicine med;
  final DateTime time;
  final DoseStatus status;
  final DoseTime slot;
}

enum VitalType { bp, sugar, weight, spo2 }

class Vital {
  Vital({required this.id, required this.memberId, required this.type, required this.at, this.a = 0, this.b = 0, this.pulse = 0, this.afterMeal = false});
  final String id;
  String memberId;
  VitalType type;
  DateTime at;
  double a; // systolic | sugar | weight | spo2
  double b; // diastolic
  double pulse;
  bool afterMeal; // sugar only
  Map<String, dynamic> toJson() => {'id': id, 'memberId': memberId, 'type': type.name, 'at': at.toIso8601String(), 'a': a, 'b': b, 'pulse': pulse, 'afterMeal': afterMeal};
  factory Vital.fromJson(Map<String, dynamic> j) => Vital(
        id: j['id'], memberId: j['memberId'], type: VitalType.values.byName(j['type']), at: _d(j['at']),
        a: (j['a'] as num).toDouble(), b: (j['b'] as num?)?.toDouble() ?? 0, pulse: (j['pulse'] as num?)?.toDouble() ?? 0, afterMeal: j['afterMeal'] ?? false,
      );
}

class Appointment {
  Appointment({required this.id, required this.memberId, required this.title, required this.place, required this.at, this.reason = '', this.notes = '', this.takeDocId, this.prescriptionDocId});
  final String id;
  String memberId, title, place, reason, notes;
  DateTime at;
  String? takeDocId, prescriptionDocId;
  Map<String, dynamic> toJson() => {
        'id': id, 'memberId': memberId, 'title': title, 'place': place, 'at': at.toIso8601String(), 'reason': reason,
        'notes': notes, 'takeDocId': takeDocId, 'prescriptionDocId': prescriptionDocId,
      };
  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'], memberId: j['memberId'], title: j['title'], place: j['place'], at: _d(j['at']), reason: j['reason'] ?? '',
        notes: j['notes'] ?? '', takeDocId: j['takeDocId'], prescriptionDocId: j['prescriptionDocId'],
      );
}

class Checkup {
  Checkup({required this.id, required this.memberId, required this.name, required this.intervalMonths, this.last, this.condition = ''});
  final String id;
  String memberId, name, condition;
  int intervalMonths;
  DateTime? last;
  DateTime? get due => last == null ? null : DateTime(last!.year, last!.month + intervalMonths, last!.day);
  Map<String, dynamic> toJson() => {'id': id, 'memberId': memberId, 'name': name, 'intervalMonths': intervalMonths, 'last': last?.toIso8601String(), 'condition': condition};
  factory Checkup.fromJson(Map<String, dynamic> j) => Checkup(
        id: j['id'], memberId: j['memberId'], name: j['name'], intervalMonths: j['intervalMonths'],
        last: j['last'] == null ? null : _d(j['last']), condition: j['condition'] ?? '',
      );
}

class ImportJob {
  ImportJob({required this.total, required this.done, required this.needReview, required this.byYear, this.paused = false, this.running = false});
  int total, done, needReview;
  bool paused, running;

  /// year -> [total, done, needReview]
  Map<int, List<int>> byYear;
  Map<String, dynamic> toJson() => {'total': total, 'done': done, 'needReview': needReview, 'paused': paused, 'byYear': byYear.map((k, v) => MapEntry('$k', v))};
  factory ImportJob.fromJson(Map<String, dynamic> j) => ImportJob(
        total: j['total'], done: j['done'], needReview: j['needReview'], paused: j['paused'] ?? false, running: false,
        byYear: (j['byYear'] as Map).map((k, v) => MapEntry(int.parse(k as String), List<int>.from(v))),
      );
}

class Prefs {
  Prefs({
    this.lang = 'en',
    this.largeText = false,
    this.voice = true,
    this.alertAdmin = true,
    this.lockEnabled = false,
    this.pinHash,
    this.darkMode = 'system',
    this.deviceUserId = '',
    this.serverHost = '',
    this.lastBackup,
    this.setupDone = false,
    this.deviceUserAsked = false,
    List<String>? healthOrder,
    this.healthOrderDirty = false,
  }) : healthOrder = healthOrder ?? [];
  String lang, darkMode, serverHost, deviceUserId;

  /// This user's order of the Health cards (`cond:<id>` / `test:<key>`; the rest
  /// follow A–Z). Kept on the account; [healthOrderDirty] until the server has it.
  List<String> healthOrder;
  bool healthOrderDirty;
  bool largeText, voice, alertAdmin, lockEnabled, setupDone;

  /// "Who uses this phone?" was answered since the last sign-in.
  bool deviceUserAsked;

  String? pinHash;
  DateTime? lastBackup;
  Map<String, dynamic> toJson() => {
        'lang': lang, 'largeText': largeText, 'voice': voice, 'alertAdmin': alertAdmin, 'lockEnabled': lockEnabled,
        'pinHash': pinHash, 'darkMode': darkMode, 'deviceUserId': deviceUserId, 'serverHost': serverHost,
        'lastBackup': lastBackup?.toIso8601String(), 'setupDone': setupDone, 'deviceUserAsked': deviceUserAsked,
        'healthOrder': healthOrder, 'healthOrderDirty': healthOrderDirty,
      };
  factory Prefs.fromJson(Map<String, dynamic> j) => Prefs(
        lang: j['lang'] ?? 'en', largeText: j['largeText'] ?? false, voice: j['voice'] ?? true, alertAdmin: j['alertAdmin'] ?? true,
        lockEnabled: j['lockEnabled'] ?? false, pinHash: j['pinHash'], darkMode: j['darkMode'] ?? 'system',
        deviceUserId: j['deviceUserId'] ?? '', serverHost: j['serverHost'] ?? '',
        lastBackup: j['lastBackup'] == null ? null : _d(j['lastBackup']), setupDone: j['setupDone'] ?? false,
        deviceUserAsked: j['deviceUserAsked'] ?? false,
        healthOrder: (j['healthOrder'] as List?)?.cast<String>(), healthOrderDirty: j['healthOrderDirty'] ?? false,
      );
}
