/// Numeric fields and their units as printed on the Cult Smart Scale report.
const cultUnits = <String, String>{
  'Weight': 'kg',
  'Health score': '',
  'BMI': 'kg/m²',
  'Fat ratio': '%',
  'Total body water': 'kg',
  'Protein mass': 'kg',
  'Fat mass': 'kg',
  'Others': 'kg',
  'Standard weight': 'kg',
  'Weight control': 'kg',
  'Fat control': 'kg',
  'Muscle control': 'kg',
  'BMR': 'kcal',
  'Visceral fat': '',
  'Chart weight': 'kg',
  'Bone mass': 'kg',
  'Muscle mass': 'kg',
  'Skeletal muscle mass': 'kg',
  'Body age': 'years',
  'Subcutaneous fat mass': 'kg',
  'Lean body mass': 'kg',
  'Height': 'cm',
  'Age': 'years',
};

class CultMeasurement {
  const CultMeasurement(this.at, this.fields);
  final DateTime at;
  final Map<String, dynamic> fields;
  double get weight => (fields['Weight'] as num).toDouble();

  static bool recognizes(String text) =>
      RegExp(r'Cult\s+Smart\s+Scale', caseSensitive: false).hasMatch(text) || (text.contains('Body composition analysis') && text.contains('Muscle control'));

  static CultMeasurement parse(String raw, String bodyType) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    RegExpMatch match(String pattern) =>
        RegExp(pattern, caseSensitive: false).firstMatch(text) ?? (throw const FormatException('Unrecognized Cult Fit report layout.'));
    const number = r'(-?\d+(?:\.\d+)?)';
    double value(String pattern) => double.parse(match(pattern)[1]!);
    final header = match(
      r'Measurement Report (.+?) (\d{4})\.(\d{1,2})\.(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\S+) gender (\d+) age ([\d.]+) cm height ([\d.]+) HEALTH SCORE',
    );
    int part(int i) => int.parse(header[i]!);
    final clock = DateTime.utc(part(2), part(3), part(4), part(5), part(6), part(7));
    if (clock.month != part(3) || clock.day != part(4) || clock.hour != part(5) || clock.minute != part(6) || clock.second != part(7)) {
      throw const FormatException('Invalid Cult Fit measurement time.');
    }
    final fields = <String, dynamic>{
      'Scale profile': header[1],
      'Gender': header[8],
      'Age': part(9),
      'Height': double.parse(header[10]!),
      'Health score': double.parse(header[11]!),
      'Weight': value('Weight\\s*-\\s*$number'),
      'Body type': bodyType,
      'Health evaluation': match(r'Health Evaluation (.+?) Lean Body Mass')[1],
    };
    for (final label in [
      'Total body water',
      'Protein mass',
      'Fat mass',
      'Others',
      'Standard weight',
      'Weight control',
      'Fat control',
      'Muscle control',
      'BMR',
      'Fat ratio',
      'Visceral fat',
      'Body age',
      'Subcutaneous fat mass',
      'Lean body mass',
    ]) {
      fields[label] = value('$label\\s+$number');
    }
    for (final entry in {
      'Chart weight': 'Weight',
      'Bone mass': 'Bone Mass',
      'Muscle mass': 'Muscle mass',
      'Skeletal muscle mass': 'Skeletal Muscle mass',
    }.entries) {
      final row = match('${entry.value}\\s*\\(kg\\)\\s+(?:\\d+\\s+)+$number\\s*\\(([^)]+)\\)');
      fields[entry.key] = double.parse(row[1]!);
      fields['${entry.key} rating'] = row[2];
    }
    final bmi = match(r'BMI\s*\(kg/m[²2]\)\s*\(([\d.]+)\s*-\s*([\d.]+)\)\s+(?:\d+\s+)+([\d.]+)\s+Body type');
    fields['BMI'] = double.parse(bmi[3]!);
    fields['BMI reference range'] = '${bmi[1]}–${bmi[2]} kg/m²';
    final at = clock.subtract(const Duration(hours: 5, minutes: 30)).toLocal();
    return CultMeasurement(at, fields);
  }
}

/// A Cult Fit number the dashboard shows: how to print it and which way is
/// better ([better] 1 = higher is better, -1 = lower is better, 0 = neither).
class CultMetric {
  const CultMetric(this.field, this.label, {this.decimals = 1, this.better = 0});
  final String field, label;
  final int decimals, better;
  String get unit => cultUnits[field] ?? '';

  /// This scan's value, or null when the report didn't have it.
  double? of(Map<String, dynamic>? fields) => switch (fields?[field]) {
    final num n when n.isFinite => n.toDouble(),
    _ => null,
  };

  String format(double v) => v.toStringAsFixed(decimals);

  /// "88.0 kg", "23.9%", "10".
  String withUnit(double v) => unit.isEmpty
      ? format(v)
      : unit == '%'
      ? '${format(v)}%'
      : '${format(v)} $unit';

  /// Signed change, e.g. "−1.2 kg" or "+0.4 pts" for a percentage.
  String change(double d) {
    final u = unit == '%'
        ? ' pts'
        : unit.isEmpty
        ? ''
        : ' $unit';
    final s = d.abs().toStringAsFixed(decimals);
    return '${d > 0
        ? '+'
        : d < 0
        ? '−'
        : ''}$s$u';
  }

  /// Whether a change of [d] went the good way (null: no direction, or no change).
  bool? improved(double d) {
    if (better == 0 || double.parse(d.abs().toStringAsFixed(decimals)) == 0) return null;
    return d * better > 0;
  }
}

/// The dashboard's headline numbers, in the order they're shown.
const cultMetrics = <CultMetric>[
  CultMetric('Weight', 'Weight', better: -1),
  CultMetric('Fat ratio', 'Body fat', better: -1),
  CultMetric('Muscle mass', 'Muscle mass', better: 1),
  CultMetric('BMI', 'BMI', better: -1),
  CultMetric('Visceral fat', 'Visceral fat', decimals: 0, better: -1),
  CultMetric('Health score', 'Health score', better: 1),
  CultMetric('Skeletal muscle mass', 'Skeletal muscle', better: 1),
  CultMetric('Lean body mass', 'Lean body mass', better: 1),
  CultMetric('Fat mass', 'Fat mass', better: -1),
  CultMetric('Subcutaneous fat mass', 'Subcutaneous fat', better: -1),
  CultMetric('Total body water', 'Body water'),
  CultMetric('Protein mass', 'Protein'),
  CultMetric('Others', 'Minerals & other'),
  CultMetric('Bone mass', 'Bone mass'),
  CultMetric('BMR', 'BMR', decimals: 0),
  CultMetric('Body age', 'Body age', decimals: 0, better: -1),
];

CultMetric cultMetric(String field) => cultMetrics.firstWhere((m) => m.field == field, orElse: () => CultMetric(field, field));

/// The report's own rating words, grouped: true = in or above the scale's
/// standard, false = outside it, null = a word this app doesn't know.
bool? cultRatingOk(String? rating) => switch (rating?.toLowerCase().trim()) {
  'standard' || 'excellent' || 'good' || 'normal' => true,
  'high' || 'low' || 'insufficient' || 'alert' || 'thin' || 'poor' => false,
  _ => null,
};

/// The 3 × 3 body-type grid as printed: rows go from less to more body fat,
/// columns from less to more muscle.
const cultBodyTypes = [
  ['Lean', 'Lean muscular', 'Muscular'],
  ['Lack of exercise', 'Standard', 'Standard muscular'],
  ['Edematous obese', 'Overweight muscular', 'Muscular overweight'],
];
