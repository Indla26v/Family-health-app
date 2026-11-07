import 'package:family_health/data/card_order.dart';
import 'package:family_health/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cards = ['LDL', 'HbA1c', 'TSH', 'Creatinine'];
  List<String> sort(List<String> order) => byUserOrder(cards, (c) => 'test:${c.toLowerCase()}', (c) => c, order);

  test('chosen cards first in the chosen order, the rest A–Z', () {
    expect(sort(['test:tsh', 'test:ldl']), ['TSH', 'LDL', 'Creatinine', 'HbA1c']);
  });

  test('no order is A–Z, unknown keys are ignored', () {
    expect(sort([]), ['Creatinine', 'HbA1c', 'LDL', 'TSH']);
    expect(sort(['test:psa', 'test:hba1c']), ['HbA1c', 'Creatinine', 'LDL', 'TSH']);
  });

  test('the order survives saving the settings', () {
    final p = Prefs.fromJson(Prefs(healthOrder: ['test:tsh'], healthOrderDirty: true).toJson());
    expect(p.healthOrder, ['test:tsh']);
    expect(p.healthOrderDirty, isTrue);
    expect(Prefs.fromJson({}).healthOrder, isEmpty);
  });
}
