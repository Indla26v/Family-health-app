import 'catalog.dart';
import 'models.dart';

StatusInfo healthReadingStatus(HealthReading r, TestDef test, Sex sex) =>
    r.isHome && (test.key == 'fbs' || test.key == 'ppbs')
    ? VitalRanges.sugar(r.value, test.key == 'ppbs')
    : labStatus(test, r.value, sex);

/// A display-only observation. Home logs stay in vitals, preserving their source
/// and avoiding duplicate lab records during sync, backup and deletion.
class HealthReading {
  const HealthReading({
    required this.id,
    required this.date,
    required this.value,
    required this.source,
    this.docId,
  });

  factory HealthReading.lab(LabResult r) => HealthReading(
    id: r.id,
    date: r.date,
    value: r.value,
    source: r.lab,
    docId: r.docId,
  );
  factory HealthReading.sugar(Vital v) => HealthReading(
    id: v.id,
    date: v.at,
    value: v.a,
    source: v.afterMeal
        ? 'Home reading · after meal'
        : 'Home reading · fasting',
  );

  final String id, source;
  final DateTime date;
  final double value;
  final String? docId;
  bool get isHome => docId == null;
}
