import 'dart:math';

import 'package:flutter/material.dart';
import 'models.dart';

/// How a value relates to its reference range. Never colour alone: every level
/// has an icon and a word as well (see StatusPill).
enum Level { normal, borderline, high, low, none }

class TestDef {
  const TestDef({
    required this.key,
    required this.name,
    required this.unit,
    required this.aliases,
    this.low,
    this.high,
    this.lowF,
    this.highF,
    this.target,
    this.group = 'other',
    this.refLabel,
    this.decimals = 1,
    this.conv = const {},
  });
  final String key, name, unit, group;
  final List<String> aliases;
  final double? low, high, lowF, highF;

  /// A personal target that is looser than the normal range (e.g. HbA1c under 7.0).
  final double? target;
  final String? refLabel;
  final int decimals;

  /// Other units labs print this test in, as the factor that turns them into
  /// [unit]. Keys are written the way the parser normalises units.
  final Map<String, double> conv;

  double? lowFor(Sex s) => s == Sex.female ? (lowF ?? low) : low;
  double? highFor(Sex s) => s == Sex.female ? (highF ?? high) : high;

  String refText(Sex s) {
    if (refLabel != null) return refLabel!;
    final l = lowFor(s), h = highFor(s);
    String f(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    if (l != null && h != null) return '${f(l)}–${f(h)}';
    if (h != null) return '< ${f(h)}';
    if (l != null) return '> ${f(l)}';
    return '';
  }

  /// Plausible bounds, used to flag mis-read values for review.
  bool plausible(double v) {
    final hi = (high ?? low ?? 100) * 20;
    return v > 0 && v < (hi <= 0 ? 10000 : hi);
  }

  Level levelOf(double v, Sex s) {
    final l = lowFor(s), h = highFor(s);
    if (l != null && v < l) return Level.low;
    if (h != null && v > h) return Level.high;
    return Level.normal;
  }
}

const labTests = <TestDef>[
  TestDef(key: 'hba1c', name: 'HbA1c', unit: '%', high: 5.7, target: 7.0, group: 'diabetes', refLabel: '< 5.7', aliases: ['hba1c', 'hbalc', 'hbaic', 'glycosylated hemoglobin', 'glycated hemoglobin', 'glycosylated haemoglobin', 'glycated haemoglobin', 'glycohemoglobin', 'a1c']),
  TestDef(key: 'fbs', name: 'Fasting glucose (FBS)', unit: 'mg/dL', low: 70, high: 100, group: 'diabetes', decimals: 0, aliases: ['fasting blood sugar', 'fasting blood glucose', 'fasting plasma glucose', 'glucose fasting', 'glucose, fasting', 'blood sugar fasting', 'blood sugar (fasting)', 'fbs', 'fbg'], conv: {'mmol/l': 18.016}),
  TestDef(key: 'ppbs', name: 'Post-prandial glucose (PPBS)', unit: 'mg/dL', low: 70, high: 140, group: 'diabetes', decimals: 0, aliases: ['post prandial plasma glucose', 'postprandial plasma glucose', 'post-prandial plasma glucose', 'post-prandial glucose', 'post-prandial blood sugar', 'post prandial blood sugar', 'postprandial blood sugar', 'post prandial glucose', 'postprandial glucose', 'post meal glucose', 'ppbs', 'pp blood sugar', 'ppbg', 'blood sugar pp'], conv: {'mmol/l': 18.016}),
  TestDef(key: 'ldl', name: 'LDL cholesterol', unit: 'mg/dL', high: 100, group: 'cholesterol', decimals: 0, aliases: ['ldl cholesterol', 'ldl-c', 'ldl direct', 'ldl', 'low density lipoprotein'], conv: {'mmol/l': 38.67}),
  TestDef(key: 'hdl', name: 'HDL cholesterol', unit: 'mg/dL', low: 40, lowF: 50, group: 'cholesterol', decimals: 0, aliases: ['hdl cholesterol', 'hdl-c', 'hdl direct', 'hdl', 'high density lipoprotein'], conv: {'mmol/l': 38.67}),
  TestDef(key: 'tc', name: 'Total cholesterol', unit: 'mg/dL', high: 200, group: 'cholesterol', decimals: 0, aliases: ['cholesterol, total', 'cholesterol total', 'total cholesterol', 'serum cholesterol', 'cholesterol'], conv: {'mmol/l': 38.67}),
  TestDef(key: 'tg', name: 'Triglycerides', unit: 'mg/dL', high: 150, group: 'cholesterol', decimals: 0, aliases: ['triglycerides', 'triglyceride', 'tgl', 'tg'], conv: {'mmol/l': 88.57}),
  TestDef(key: 'vldl', name: 'VLDL cholesterol', unit: 'mg/dL', high: 30, group: 'cholesterol', decimals: 0, aliases: ['vldl cholesterol', 'vldl'], conv: {'mmol/l': 38.67}),
  TestDef(key: 'tsh', name: 'TSH', unit: 'µIU/mL', low: 0.4, high: 4.0, group: 'thyroid', decimals: 2, aliases: ['thyroid stimulating hormone', 'tsh (ultrasensitive)', 'tsh ultrasensitive', 'tsh'], conv: {'uiu/ml': 1, 'ulu/ml': 1, 'miu/l': 1, 'mu/l': 1}),
  TestDef(key: 't3', name: 'Total T3', unit: 'ng/mL', low: 0.8, high: 2.0, group: 'thyroid', decimals: 2, aliases: ['total t3', 'triiodothyronine', 't3 total', 't3'], conv: {'ng/dl': 0.01, 'nmol/l': 0.651}),
  TestDef(key: 't4', name: 'Total T4', unit: 'µg/dL', low: 5.1, high: 14.1, group: 'thyroid', aliases: ['total t4', 'thyroxine', 't4 total', 't4'], conv: {'nmol/l': 0.0777}),
  TestDef(key: 'vitd', name: 'Vitamin D', unit: 'ng/mL', low: 30, high: 100, group: 'vitamins', decimals: 0, aliases: ['25-oh vitamin d', '25 hydroxy vitamin d', '25-hydroxy vitamin d', 'vitamin d (25-oh)', 'vitamin d total', 'vitamin d', 'vit d', '25(oh) vitamin d'], conv: {'nmol/l': 0.4006}),
  TestDef(key: 'b12', name: 'Vitamin B12', unit: 'pg/mL', low: 211, high: 911, group: 'vitamins', decimals: 0, aliases: ['vitamin b12', 'vitamin b-12', 'vit b12', 'cyanocobalamin', 'b12'], conv: {'pmol/l': 1.355}),
  TestDef(key: 'psa', name: 'PSA (prostate)', unit: 'ng/mL', high: 4.0, group: 'prostate', decimals: 2, aliases: ['prostate specific antigen', 'psa total', 'psa'], conv: {'ug/l': 1}),
  TestDef(key: 'creat', name: 'Creatinine', unit: 'mg/dL', low: 0.7, high: 1.3, lowF: 0.6, highF: 1.1, group: 'kidney', decimals: 2, aliases: ['s. creatinine', 'serum creatinine', 'creatinine'], conv: {'umol/l': 1 / 88.42}),
  TestDef(key: 'urea', name: 'Urea', unit: 'mg/dL', low: 15, high: 40, group: 'kidney', decimals: 0, aliases: ['blood urea nitrogen', 'blood urea', 'urea'], conv: {'mmol/l': 6.006}),
  TestDef(key: 'uacr', name: 'Urine microalbumin', unit: 'mg/L', high: 30, group: 'kidney', decimals: 0, aliases: ['micro albumin (urine)', 'microalbumin (urine)', 'urine microalbumin', 'microalbumin', 'urine albumin']),
  TestDef(key: 'na', name: 'Sodium', unit: 'mmol/L', low: 135, high: 145, group: 'kidney', decimals: 0, aliases: ['sodium', 'na+'], conv: {'meq/l': 1}),
  TestDef(key: 'k', name: 'Potassium', unit: 'mmol/L', low: 3.5, high: 5.1, group: 'kidney', aliases: ['potassium', 'k+'], conv: {'meq/l': 1}),
  TestDef(key: 'hb', name: 'Haemoglobin', unit: 'g/dL', low: 13, high: 17, lowF: 12, highF: 15, group: 'blood', aliases: ['haemoglobin', 'hemoglobin', 'hb'], conv: {'g/l': 0.1}),
  TestDef(key: 'uric', name: 'Uric acid', unit: 'mg/dL', low: 3.5, high: 7.2, lowF: 2.6, highF: 6.0, group: 'other', aliases: ['uric acid'], conv: {'umol/l': 1 / 59.48}),
  TestDef(key: 'alt', name: 'ALT (SGPT)', unit: 'U/L', high: 50, group: 'liver', decimals: 0, aliases: ['alanine aminotransferase', 'sgpt (alt)', 'sgpt', 'alt']),
  TestDef(key: 'ast', name: 'AST (SGOT)', unit: 'U/L', high: 50, group: 'liver', decimals: 0, aliases: ['aspartate aminotransferase', 'sgot (ast)', 'sgot', 'ast']),
];

TestDef? testByKey(String key) {
  for (final t in labTests) {
    if (t.key == key) return t;
  }
  return null;
}

/// Condition cards on the Health tab.
class ConditionDef {
  const ConditionDef(this.id, this.en, this.te, this.icon, {this.keyTest, this.emptyHint = 'No report yet'});
  final String id, en, te;
  final IconData icon;
  final String? keyTest;
  final String emptyHint;
}

const conditionDefs = <ConditionDef>[
  ConditionDef('diabetes', 'Diabetes', 'మధుమేహం', Icons.water_drop_rounded, keyTest: 'hba1c'),
  ConditionDef('bp', 'Blood pressure', 'రక్తపోటు', Icons.monitor_heart_rounded),
  ConditionDef('cholesterol', 'Cholesterol', 'కొలెస్ట్రాల్', Icons.insights_rounded, keyTest: 'ldl'),
  ConditionDef('thyroid', 'Thyroid', 'థైరాయిడ్', Icons.insights_rounded, keyTest: 'tsh'),
  ConditionDef('vitamins', 'Vitamins', 'విటమిన్లు', Icons.wb_sunny_rounded, keyTest: 'vitd'),
  ConditionDef('prostate', 'Prostate', 'ప్రోస్టేట్', Icons.description_rounded, keyTest: 'psa', emptyHint: 'No PSA report yet'),
  ConditionDef('gallbladder', 'Gall bladder', 'పిత్తాశయం', Icons.description_rounded, emptyHint: 'No ultrasound report yet'),
];

ConditionDef conditionById(String id) => conditionDefs.firstWhere((c) => c.id == id);

/// Pill content: level + word + icon (never colour alone).
class StatusInfo {
  const StatusInfo(this.level, this.word);
  final Level level;
  final String word;
}

/// Thresholds below are placeholders drawn from common Indian clinical
/// guidance and the family's mock data; the family's doctor should confirm them.
class VitalRanges {
  static StatusInfo bp(double sys, double dia) {
    if (sys >= 140 || dia >= 90) return const StatusInfo(Level.high, 'High');
    if (sys < 90 || dia < 60) return const StatusInfo(Level.low, 'Low');
    if (sys >= 130 || dia >= 85) return const StatusInfo(Level.borderline, 'Borderline');
    return const StatusInfo(Level.normal, 'Normal');
  }

  static StatusInfo sugar(double v, bool afterMeal) {
    if (v < 70) return const StatusInfo(Level.low, 'Low');
    if (afterMeal) {
      if (v >= 200) return const StatusInfo(Level.high, 'High');
      if (v >= 140) return const StatusInfo(Level.borderline, 'Borderline');
      return const StatusInfo(Level.normal, 'Normal');
    }
    if (v >= 120) return const StatusInfo(Level.high, 'High');
    if (v >= 100) return const StatusInfo(Level.borderline, 'Borderline');
    return const StatusInfo(Level.normal, 'Normal');
  }

  static StatusInfo spo2(double v) {
    if (v < 90) return const StatusInfo(Level.low, 'Low');
    if (v < 95) return const StatusInfo(Level.borderline, 'Borderline');
    return const StatusInfo(Level.normal, 'Normal');
  }

  static String bpNote(StatusInfo s) => switch (s.level) {
        Level.normal => 'Under 130/85',
        Level.borderline => 'Slightly above 130/85',
        Level.high => 'At or above 140/90',
        Level.low => 'Below 90/60',
        Level.none => '',
      };
  static String sugarNote(StatusInfo s) => switch (s.level) {
        Level.normal => 'In usual range',
        Level.borderline => 'A little above usual range',
        Level.high => 'Above usual range',
        Level.low => 'Below 70 mg/dL',
        Level.none => '',
      };
  static String spo2Note(StatusInfo s) => switch (s.level) {
        Level.normal => '95% or more',
        Level.borderline => 'Between 90 and 94%',
        Level.low => 'Below 90%',
        _ => '',
      };

  static StatusInfo ofVital(Vital v) => switch (v.type) {
        VitalType.bp => bp(v.a, v.b),
        VitalType.sugar => sugar(v.a, v.afterMeal),
        VitalType.spo2 => spo2(v.a),
        VitalType.weight => const StatusInfo(Level.none, 'Steady'),
      };
}

/// Status for a lab result, honouring a looser personal target (HbA1c).
StatusInfo labStatus(TestDef t, double v, Sex sex) {
  if (t.target != null) {
    final base = t.levelOf(v, sex);
    if (base == Level.normal) return const StatusInfo(Level.normal, 'Normal');
    if (v <= t.target!) return const StatusInfo(Level.normal, 'Under target');
    return const StatusInfo(Level.high, 'Above target');
  }
  return switch (t.levelOf(v, sex)) {
    Level.high => const StatusInfo(Level.high, 'High'),
    Level.low => const StatusInfo(Level.low, 'Low'),
    _ => const StatusInfo(Level.normal, 'Normal'),
  };
}

/// [v] with at least [decimals] places, and more (up to two) when the value has
/// them, so a printed 9.03 or 66.4 is never shown rounded to 9.0 or 66.
String fmtNum(double v, [int decimals = 1]) {
  var d = decimals;
  while (d < 2 && ((v * _pow10[d]).roundToDouble() - v * _pow10[d]).abs() > 1e-6) {
    d++;
  }
  return v.toStringAsFixed(d);
}

const _pow10 = [1, 10, 100];

/// Lab values are always shown with two decimals (125.00 mg/dL, 1.08 ng/mL).
String fmtVal(TestDef t, double v) => v.toStringAsFixed(2);

String canonUnit(String u) => u.toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp('[µμ]'), 'u');

final _onReport = RegExp(r'\s*\(([\d.]+) ([^()]+) on report\)$');

/// Whether [v] × [f] sits closer to the test's normal range than [v] does: a
/// value really in the other unit (108 ng/dL) gets converted, while one that was
/// only labelled with the wrong unit (0.83 "ng/dL", as old app versions saved
/// ng/mL T3) keeps its number and just gets the right label.
bool _convertBetter(TestDef def, double v, double f) {
  final lo = def.low, hi = def.high;
  final mid = lo != null && hi != null ? sqrt(lo * hi) : (hi != null ? hi * .7 : (lo != null ? lo * 1.5 : null));
  if (mid == null || v <= 0) return true;
  double dist(double x) => (log(x / mid)).abs();
  return dist(v * f) < dist(v);
}

/// Brings a stored result into its test's standard unit (value and reference
/// range), e.g. a T3 saved in ng/dL by an older version → ng/mL. A "(… on report)"
/// note is dropped once the stored unit is the one printed on the report again.
/// Returns whether anything changed.
bool normalizeLab(LabResult l) {
  final def = testByKey(l.testKey);
  if (def == null) return false;
  var changed = false;
  final f = canonUnit(l.unit) == canonUnit(def.unit) ? null : def.conv[canonUnit(l.unit)];
  if (f != null) {
    String num(double n) => _convertBetter(def, n, f) ? fmtNum(n * f, def.decimals) : fmtNum(n, def.decimals);
    l
      ..value = _convertBetter(def, l.value, f) ? (l.value * f * 1e4).roundToDouble() / 1e4 : l.value
      ..unit = def.unit
      ..refText = l.refText.replaceAllMapped(RegExp(r'\d+(?:\.\d+)?'), (m) => num(double.parse(m.group(0)!)))
      ..checkNote = l.checkNote.startsWith('Unit on the page') ? '' : l.checkNote;
    changed = true;
  }
  final m = _onReport.firstMatch(l.rawName);
  if (m != null && canonUnit(m.group(2)!) == canonUnit(l.unit)) {
    l.rawName = l.rawName.substring(0, m.start);
    changed = true;
  }
  return changed;
}
