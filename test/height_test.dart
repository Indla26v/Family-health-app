import 'package:family_health/data/catalog.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/ui/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('height shows in cm and feet/inches', () {
    expect(feetInches(180.34), (5, 11));
    expect(feetInches(152.4), (5, 0));
    expect(fmtHeight(180.34), '180 cm · 5′11″');
  });

  test('stored T3: a real ng/dL value converts; a mislabelled one keeps its number', () {
    LabResult t3(double v, String ref, String raw) => LabResult(id: 'x', memberId: 'm', testKey: 't3', value: v, unit: 'ng/dL', date: DateTime(2026), docId: 'd', lab: 'L', refText: ref, rawName: raw);
    final real = t3(108, '60 - 178', 'T3 (1.08 ng/ml on report)');
    expect(normalizeLab(real), isTrue);
    expect((real.value, real.unit, real.refText, real.rawName), (1.08, 'ng/mL', '0.60 - 1.78', 'T3'));
    final mislabelled = t3(0.83, '60 - 178', 'T3 (0.83 ng/ml on report)');
    normalizeLab(mislabelled);
    expect((mislabelled.value, mislabelled.unit, mislabelled.refText, mislabelled.rawName), (0.83, 'ng/mL', '0.60 - 1.78', 'T3'));
    expect(fmtVal(testByKey('tc')!, 125), '125.00');
  });
}
