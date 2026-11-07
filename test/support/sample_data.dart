import 'dart:math';

import 'package:family_health/core/theme.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/data/store.dart';

/// Test fixture: the family from the design brief (no health data).
void seedEmptyFamily(AppStore s) {
  s.members = [
    Member(id: 'father', name: 'Father', initial: 'F', age: 60, bloodGroup: 'B+', sex: Sex.male, role: Role.simple, color: MemberColors.father,
        conditions: ['diabetes', 'bp', 'cholesterol', 'thyroid', 'vitamins', 'prostate', 'gallbladder'],
        contacts: [Contact('Son', 'Admin', ''), Contact('Daughter', 'Family', '')]),
    Member(id: 'mother', name: 'Mother', initial: 'M', age: 54, bloodGroup: 'O+', sex: Sex.female, role: Role.simple, color: MemberColors.mother,
        conditions: ['diabetes', 'bp', 'cholesterol', 'vitamins'],
        contacts: [Contact('Son', 'Admin', ''), Contact('Daughter', 'Family', '')]),
    Member(id: 'daughter', name: 'Daughter', initial: 'D', age: 24, bloodGroup: 'B+', sex: Sex.female, role: Role.full, color: MemberColors.daughter,
        contacts: [Contact('Son', 'Admin', ''), Contact('Father', 'Family', '')]),
    Member(id: 'son', name: 'Son', initial: 'S', age: 21, bloodGroup: 'O+', sex: Sex.male, role: Role.admin, color: MemberColors.son,
        contacts: [Contact('Father', 'Family', ''), Contact('Mother', 'Family', '')]),
  ];
  s.prefs.deviceUserId = 'son';
  s.prefs.setupDone = true;
}

const _thyro = 'Thyrocare', _vij = 'Vijaya Diagnostics', _apo = 'Apollo Clinic';

/// Test fixture: the mock data from the design brief. Never shipped in the app.
void seedDemoData(AppStore s) {
  seedEmptyFamily(s);
  final now = DateTime.now();
  final today = dayOnly(now);
  final rng = Random(42);
  var n = 0;
  String id(String p) => '$p${n++}';

  // ---- Lab history ---------------------------------------------------------
  void report(String member, DateTime date, String lab, int tests, Map<String, double> values, {DocStatus st = DocStatus.parsed}) {
    final did = id('doc');
    s.docs.add(Doc(id: did, memberId: member, lab: lab, date: date, kind: DocKind.lab, status: st, testCount: tests, pages: 3));
    values.forEach((k, v) {
      s.labs.add(LabResult(id: id('lab'), memberId: member, testKey: k, value: v, unit: _unit(k), date: date, docId: did, lab: lab));
    });
  }

  report('father', DateTime(2020, 10, 5), _thyro, 14, {'hba1c': 8.5, 'fbs': 168, 'ppbs': 250});
  report('father', DateTime(2021, 9, 14), _vij, 15, {'hba1c': 8.1, 'fbs': 156, 'ppbs': 232});
  report('father', DateTime(2022, 5, 9), _thyro, 18, {'hba1c': 7.8, 'fbs': 148, 'ppbs': 218, 'ldl': 148});
  report('father', DateTime(2023, 2, 22), _vij, 20, {'hba1c': 7.4, 'fbs': 140, 'ppbs': 204, 'ldl': 132, 'tsh': 5.8, 'vitd': 14});
  report('father', DateTime(2024, 4, 6), _apo, 16, {'hba1c': 7.1, 'fbs': 134, 'ppbs': 190, 'ldl': 118, 'tsh': 4.6, 'vitd': 19});
  report('father', DateTime(2025, 3, 18), _thyro, 22, {'hba1c': 6.9, 'fbs': 128, 'ppbs': 178, 'ldl': 104, 'tsh': 3.9, 'vitd': 26});
  report('father', DateTime(2026, 3, 14), _thyro, 24, {'tsh': 3.2, 'vitd': 31, 'creat': 1.0, 'urea': 28});
  report('father', DateTime(2026, 9, 12), _vij, 18,
      {'hba1c': 6.8, 'fbs': 124, 'ppbs': 165, 'ldl': 96, 'hdl': 44, 'tc': 162, 'tg': 148, 'na': 139});

  report('mother', DateTime(2022, 6, 11), _vij, 12, {'hba1c': 7.9, 'fbs': 142});
  report('mother', DateTime(2023, 6, 20), _vij, 12, {'hba1c': 7.5, 'fbs': 136});
  report('mother', DateTime(2024, 6, 18), _thyro, 14, {'hba1c': 7.2, 'fbs': 128, 'ldl': 122});
  report('mother', DateTime(2025, 6, 14), _vij, 12, {'hba1c': 7.0, 'fbs': 120, 'ldl': 110});
  report('mother', DateTime(2026, 6, 16), _vij, 14, {'hba1c': 6.9, 'fbs': 116, 'ldl': 98, 'vitd': 24});

  // Needs review: Apollo Clinic, 2 Aug 2026 (the review screen from the design)
  final apollo = id('doc');
  s.docs.add(Doc(id: apollo, memberId: 'father', lab: _apo, date: DateTime(2026, 8, 2), kind: DocKind.lab, status: DocStatus.needsReview, testCount: 9, pages: 2));
  void pending(String key, String raw, double v, String unit, String ref, {double conf = .97, String note = ''}) => s.labs.add(LabResult(
      id: id('lab'), memberId: 'father', testKey: key, value: v, unit: unit, date: DateTime(2026, 8, 2), docId: apollo, lab: _apo,
      rawName: raw, confidence: conf, confirmed: false, checkNote: note, refText: ref));
  pending('tg', 'TGL', 162, 'mg/dL', '< 150', conf: .55, note: 'Value looked like “1 62” — please check');
  pending('uacr', 'Micro Albumin (Urine)', 24, 'mg/L', '< 30', conf: .6, note: 'Unit was unclear on the page — please check');
  pending('fbs', 'FBS (GOD-POD)', 128, 'mg/dL', '70–100');
  pending('ppbs', 'Post Prandial Blood Sugar', 172, 'mg/dL', '< 140');
  pending('tc', 'Cholesterol, Total', 168, 'mg/dL', '< 200');
  pending('hdl', 'HDL-C Direct', 41, 'mg/dL', '> 40');
  pending('creat', 'S. Creatinine', 1.0, 'mg/dL', '0.7–1.3');
  pending('urea', 'Blood Urea', 28, 'mg/dL', '15–40');
  pending('na', 'Na+', 139, 'mmol/L', '135–145');

  s.docs.add(Doc(id: id('doc'), memberId: 'mother', lab: 'Prescription scan', date: DateTime(2026, 7, 18), kind: DocKind.prescription, status: DocStatus.needsReview, testCount: 4, isImage: true));
  s.docs.add(Doc(id: id('doc'), memberId: 'mother', lab: _vij, date: DateTime(2025, 1, 3), kind: DocKind.lab, status: DocStatus.needsReview, testCount: 12, pages: 2));
  final presc = id('doc');
  s.docs.add(Doc(id: presc, memberId: 'father', lab: 'Prescription', date: DateTime(2026, 7, 18), kind: DocKind.prescription, status: DocStatus.parsed, testCount: 0, isImage: true));

  // Daughter's report: page 3 failed to read, pages 1–2 were read.
  final dd = id('doc');
  s.docs.add(Doc(id: dd, memberId: 'daughter', lab: 'Lab report · page 3', date: DateTime(2026, 2, 2), kind: DocKind.lab, status: DocStatus.failed, pages: 3, failedPage: 3, isImage: true));
  s.labs.add(LabResult(id: id('lab'), memberId: 'daughter', testKey: 'hb', value: 12.8, unit: 'g/dL', date: DateTime(2026, 2, 2), docId: dd, lab: 'Lab report'));
  s.labs.add(LabResult(id: id('lab'), memberId: 'daughter', testKey: 'b12', value: 210, unit: 'pg/mL', date: DateTime(2026, 2, 2), docId: dd, lab: 'Lab report'));

  s.job = ImportJob(total: 142, done: 98, needReview: 11, byYear: {
    2019: [18, 18, 2], 2020: [22, 22, 2], 2021: [20, 20, 1], 2022: [24, 24, 3], 2023: [21, 14, 3], 2024: [19, 0, 0], 2025: [18, 0, 0],
  });

  // ---- Medicines ------------------------------------------------------------
  var start = DateTime(2026, 8, 1);
  if (start.isAfter(today.subtract(const Duration(days: 60)))) start = today.subtract(const Duration(days: 60));
  if (start.isBefore(today.subtract(const Duration(days: 200)))) start = today.subtract(const Duration(days: 200));

  Medicine med(String member, String name, String strength, Food food, List<DoseTime> times, double stock, String te, {String cond = ''}) {
    final m = Medicine(id: id('med'), memberId: member, name: name, strength: strength, food: food, times: times, stock: stock, startDate: start, teluguName: te, forCondition: cond);
    s.meds.add(m);
    return m;
  }

  DoseTime am(int h, int m) => DoseTime('morning', h, m);
  DoseTime pm(int h, int m) => DoseTime('night', h, m);
  final thyronorm = med('father', 'Thyronorm', '50 mcg', Food.before, [am(6, 30)], 40, 'థైరోనార్మ్', cond: 'thyroid');
  final telmi = med('father', 'Telmisartan', '40 mg', Food.after, [am(8, 0)], 30, 'టెల్మిసార్టాన్', cond: 'bp');
  final metf = med('father', 'Metformin', '500 mg', Food.after, [am(8, 0), pm(20, 0)], 60, 'మెట్‌ఫార్మిన్', cond: 'diabetes');
  final ator = med('father', 'Atorvastatin', '10 mg', Food.any, [pm(21, 30)], 24, 'అటోర్వాస్టాటిన్', cond: 'cholesterol');
  final tams = med('father', 'Tamsulosin', '0.4 mg', Food.any, [pm(21, 30)], 6, 'టామ్సులోసిన్', cond: 'prostate');
  final mMetf = med('mother', 'Metformin', '500 mg', Food.after, [am(8, 0), pm(20, 0)], 50, 'మెట్‌ఫార్మిన్', cond: 'diabetes');
  final mAmlo = med('mother', 'Amlodipine', '5 mg', Food.any, [am(8, 0)], 28, 'అమ్లోడిపిన్', cond: 'bp');
  final mAtor = med('mother', 'Atorvastatin', '10 mg', Food.any, [pm(21, 30)], 28, 'అటోర్వాస్టాటిన్', cond: 'cholesterol');
  final mCalc = med('mother', 'Calcium', '500 mg', Food.after, [DoseTime('afternoon', 13, 30)], 40, 'కాల్షియం', cond: 'vitamins');

  // Dose history: taken, except the handful of misses shown on the Adherence screen.
  final misses = <String>{
    '${dayKey(DateTime(2026, 9, 5))}|${metf.id}|20:0',
    '${dayKey(DateTime(2026, 9, 12))}|${thyronorm.id}|6:30',
    '${dayKey(DateTime(2026, 9, 19))}|${tams.id}|21:30',
    '${dayKey(DateTime(2026, 9, 23))}|${ator.id}|21:30',
    '${dayKey(DateTime(2026, 9, 28))}|${telmi.id}|8:0',
    '${dayKey(DateTime(2026, 9, 28))}|${metf.id}|20:0',
    '${dayKey(today)}|${metf.id}|8:0', // this morning, for the missed-dose banner
  };
  for (final m in [thyronorm, telmi, metf, ator, tams, mMetf, mAmlo, mAtor, mCalc]) {
    for (var d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      for (final t in m.times) {
        final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        final isToday = d == today;
        if (isToday && !now.isAfter(at.add(const Duration(minutes: 90)))) continue;
        if (!isToday || now.isAfter(at)) {
          final key = '${dayKey(d)}|${m.id}|${t.key}';
          if (misses.contains(key)) continue;
          if (m.memberId == 'mother' && rng.nextInt(40) == 0) continue;
          final log = DoseLog(medId: m.id, memberId: m.memberId, day: dayKey(d), timeKey: t.key, state: DoseState.taken, at: at.add(Duration(minutes: 1 + rng.nextInt(10))));
          s.logs[log.key] = log;
        }
      }
    }
  }

  // ---- Vitals ----------------------------------------------------------------
  void bp(String member, DateTime at, double sys, double dia, double pulse) =>
      s.vitals.add(Vital(id: id('v'), memberId: member, type: VitalType.bp, at: at, a: sys, b: dia, pulse: pulse));
  void sugar(String member, DateTime at, double v, bool after) =>
      s.vitals.add(Vital(id: id('v'), memberId: member, type: VitalType.sugar, at: at, a: v, afterMeal: after));
  DateTime at(DateTime d, int h, int m) => DateTime(d.year, d.month, d.day, h, m);
  DateTime morning(int daysAgo, int h, int m) {
    final d = today.subtract(Duration(days: daysAgo));
    return at(d, h, m);
  }

  for (var i = 60; i >= 1; i--) {
    bp('father', morning(i, 7, 40), 128 + rng.nextInt(14).toDouble(), 80 + rng.nextInt(9).toDouble(), 70 + rng.nextInt(10).toDouble());
    bp('mother', morning(i, 7, 30), 122 + rng.nextInt(10).toDouble(), 76 + rng.nextInt(7).toDouble(), 72 + rng.nextInt(8).toDouble());
  }
  var todayAt = at(today, 7, 40);
  if (todayAt.isAfter(now)) todayAt = todayAt.subtract(const Duration(days: 1));
  bp('father', todayAt, 138, 86, 74);
  bp('mother', todayAt.subtract(const Duration(minutes: 10)), 128, 80, 72);
  sugar('father', todayAt.subtract(const Duration(minutes: 45)), 124, false);
  sugar('mother', todayAt.subtract(const Duration(minutes: 40)), 112, false);
  for (var mo = 12; mo >= 0; mo--) {
    for (var k = 0; k < 8; k++) {
      final d = today.subtract(Duration(days: mo * 30 + k * 3 + 1));
      sugar('father', at(d, 7, 0), 124 + mo * 2.2 + rng.nextInt(13) - 6, false);
      if (k % 3 == 0) sugar('father', at(d, 14, 0), 165 + mo * 2.0 + rng.nextInt(21) - 10, true);
      sugar('mother', at(d, 7, 0), 112 + mo * 1.4 + rng.nextInt(11) - 5, false);
    }
  }
  for (var w = 12; w >= 0; w--) {
    final d = today.subtract(Duration(days: w * 7 + 2));
    s.vitals.add(Vital(id: id('v'), memberId: 'father', type: VitalType.weight, at: at(d, 7, 15), a: 84 + w * 0.12 + (rng.nextInt(5) - 2) * 0.1));
    s.vitals.add(Vital(id: id('v'), memberId: 'mother', type: VitalType.weight, at: at(d, 7, 20), a: 66 + (rng.nextInt(5) - 2) * 0.1));
  }
  s.vitals.removeWhere((v) => v.type == VitalType.weight && v.memberId == 'father' && v.at.isAfter(today.subtract(const Duration(days: 2))));
  s.vitals.add(Vital(id: id('v'), memberId: 'father', type: VitalType.weight, at: at(today.subtract(const Duration(days: 2)), 7, 15), a: 84));

  // ---- Appointments ------------------------------------------------------------
  final latestVij = s.docs.firstWhere((d) => d.lab == _vij && d.date == DateTime(2026, 9, 12));
  s.appts.addAll([
    Appointment(id: id('ap'), memberId: 'father', title: 'Endocrinologist', place: 'SVIMS Tirupati', at: DateTime(2026, 10, 20, 10, 30), reason: 'HbA1c review', takeDocId: latestVij.id),
    Appointment(id: id('ap'), memberId: 'mother', title: 'Gynaecology follow-up', place: '', at: DateTime(2026, 11, 7, 10, 0), reason: 'Routine follow-up'),
    Appointment(id: id('ap'), memberId: 'father', title: 'Endocrinologist', place: 'SVIMS Tirupati', at: DateTime(2026, 7, 18, 11, 0), notes: 'Continue Metformin 500 mg twice daily. Repeat HbA1c in 3 months.', prescriptionDocId: presc),
    Appointment(id: id('ap'), memberId: 'daughter', title: 'Annual check-up', place: 'Apollo Clinic', at: DateTime(2026, 2, 2, 9, 0)),
  ]);

  // ---- Preventive check-ups ----------------------------------------------------
  void cu(String member, String name, int months, DateTime? last, {String cond = ''}) =>
      s.checkups.add(Checkup(id: id('cu'), memberId: member, name: name, intervalMonths: months, last: last, condition: cond));
  cu('father', 'Eye check (retina)', 12, DateTime(2025, 3, 14), cond: 'diabetes');
  cu('father', 'Kidney check (urine ACR)', 6, DateTime(2026, 8, 2), cond: 'diabetes');
  cu('father', 'Foot check', 12, null, cond: 'diabetes');
  cu('father', 'Lipid profile', 6, DateTime(2026, 9, 12), cond: 'cholesterol');
  cu('mother', 'Eye check (retina)', 12, DateTime(2025, 11, 20), cond: 'diabetes');
  cu('mother', 'Kidney check (urine ACR)', 6, DateTime(2026, 1, 9), cond: 'diabetes');
  cu('mother', 'Foot check', 12, null, cond: 'diabetes');
  cu('mother', 'Mammogram', 24, null);
  cu('daughter', 'Annual blood test', 12, DateTime(2026, 2, 2));
  cu('daughter', 'Eye check', 24, null);
  cu('daughter', 'Dental check-up', 6, DateTime(2026, 5, 4));
  cu('son', 'Annual blood test', 12, null);
  cu('son', 'Eye check', 24, null);
  cu('son', 'Dental check-up', 6, null);

  for (final m in s.members) {
    if (m.id == 'father') m.heightCm = null;
  }
  s.prefs.lastBackup = null;
}

String _unit(String key) => switch (key) {
      'hba1c' => '%',
      'tsh' => 'µIU/mL',
      'vitd' => 'ng/mL',
      'creat' => 'mg/dL',
      'urea' => 'mg/dL',
      'na' => 'mmol/L',
      'hb' => 'g/dL',
      'b12' => 'pg/mL',
      _ => 'mg/dL',
    };
