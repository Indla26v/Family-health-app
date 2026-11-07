import 'package:family_health/data/catalog.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/data/store.dart';
import 'package:family_health/services/parser.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_data.dart';

const _sample = '''
VIJAYA DIAGNOSTIC CENTRE
Patient Name : Mr. Ramesh Kumar        Age : 60 Yrs   Sex : Male
Sample Collected On : 12/09/2026 08:10
Reported On : 12-Sep-2026
TEST NAME                     RESULT     UNITS      BIOLOGICAL REF. INTERVAL
Glycosylated Hemoglobin (HbA1c)   6.8     %          < 5.7
Fasting Blood Sugar (GOD-POD)     124     mg/dL      70 - 100
Post Prandial Blood Sugar         165     mg/dl      < 140
LDL Cholesterol                   96      mg/dL      < 100
HDL Cholesterol                   44      mg/dL      > 40
Cholesterol, Total                162     mg/dL      < 200
Triglycerides                     148     mg/dL      < 150
Cholesterol/HDL Ratio             3.7                < 5.0
TSH (Ultrasensitive)              3.2     µIU/mL     0.4 - 4.0
Vitamin D (25-OH)                 31      ng/mL      30 - 100
Serum Creatinine                  1.0                0.7 - 1.3
''';

void main() {
  group('ReportParser', () {
    final r = ReportParser.parse(_sample);
    double v(String k) => r.tests.firstWhere((t) => t.testKey == k).value;

    test('finds lab, date and patient', () {
      expect(r.lab, 'Vijaya Diagnostics');
      expect(r.date, DateTime(2026, 9, 12));
      expect(r.patientName, 'Ramesh Kumar');
    });

    test('reads values against canonical tests', () {
      expect(v('hba1c'), 6.8);
      expect(v('fbs'), 124);
      expect(v('ppbs'), 165);
      expect(v('ldl'), 96);
      expect(v('hdl'), 44);
      expect(v('tc'), 162);
      expect(v('tg'), 148);
      expect(v('tsh'), 3.2);
      expect(v('vitd'), 31);
    });

    test('skips ratio lines and does not confuse total with HDL/LDL', () {
      expect(r.tests.where((t) => t.testKey == 'tc').length, 1);
      expect(v('tc'), isNot(3.7));
    });

    test('flags a missing unit for review', () {
      final cr = r.tests.firstWhere((t) => t.testKey == 'creat');
      expect(cr.value, 1.0);
      expect(cr.confidence, lessThan(0.8));
      expect(cr.note, contains('Unit'));
      final ldl = r.tests.firstWhere((t) => t.testKey == 'ldl');
      expect(ldl.confidence, greaterThanOrEqualTo(0.8));
    });

    test('handles the Friends Diagnostics layout', () {
      final f = ReportParser.parse('''
Ref Doctor  : SELF  Collected  : 2026-06-30 10:31
H D L CHOLESTEROL  39  mg/dl  > 40  Enzymatic/
L D L CHOLESTEROL  88.8  mg/dl  See Refer Table below
NON HDL CHOLESTEROL  109  mg/dl  < 130  Calculated
FASTING PLASMA GLUCOSE  mg/dl  70 - 100  Hexokinase
T3  1.08  ng/ml  0.60 - 1.78  CLIA
TSH  2.25  ulU/mL  0.3 - 5.6  CLIA
SERUM SODIUM  139.9  mEq/L  136-145  ISE
''');
      ExtractedTest? t(String k) => f.tests.where((x) => x.testKey == k).firstOrNull;
      expect(f.date, DateTime(2026, 6, 30));
      expect(t('hdl')?.value, 39); // not the Non-HDL 109
      expect(t('ldl')?.value, 88.8);
      expect(t('fbs'), isNull); // 70 is the range start, not a result
      expect(t('t3')?.value, 1.08); // ng/mL is the standard unit
      expect(t('t3')?.refText, '0.60 - 1.78');
      expect(t('t3')?.confidence, 0.96);
      expect(t('t3')?.note, '');
      expect(t('t3')?.rawName, 'T3');
      final dl = ReportParser.parse('TOTAL T3  108  ng/dL  60 - 200').tests.single;
      expect((dl.value, dl.unit, dl.refText), (1.08, 'ng/mL', '0.60 - 2.00'));
      expect(t('tsh')?.confidence, 0.96);
      expect(t('na')?.unit, 'mmol/L');
      expect(t('na')?.confidence, 0.96);
      final pp = ReportParser.parse('''PPBS (POST PRANDIAL GLUCOSE)
POST PRANDIAL PLASMA GLUCOSE  216  mg/dl  < 140  HEXOKINASE
FASTING PLASMA GLUCOSE  143  mg/dl  70 - 100''');
      expect(pp.tests.firstWhere((x) => x.testKey == 'ppbs').value, 216);
      expect(pp.tests.firstWhere((x) => x.testKey == 'fbs').value, 143);
    });

    test('name matching', () {
      final m = Member(id: 'f', name: 'Father', initial: 'F', age: 60, bloodGroup: 'B+', sex: Sex.male, role: Role.simple, color: const Color(0xFF000000), fullName: 'Ramesh Kumar');
      expect(ReportParser.nameMatches('Ramesh Kumar', m), isTrue);
      expect(ReportParser.nameMatches('Lakshmi Devi', m), isFalse);
    });
  });

  group('ranges', () {
    test('BP and sugar match the brief', () {
      expect(VitalRanges.bp(138, 86).word, 'Borderline');
      expect(VitalRanges.bp(128, 80).word, 'Normal');
      expect(VitalRanges.bp(145, 92).word, 'High');
      expect(VitalRanges.sugar(124, false).word, 'High');
      expect(VitalRanges.sugar(112, false).word, 'Borderline');
    });

    test('HbA1c uses the personal target', () {
      final t = testByKey('hba1c')!;
      expect(labStatus(t, 6.8, Sex.male).word, 'Under target');
      expect(labStatus(t, 7.4, Sex.male).word, 'Above target');
      expect(labStatus(t, 5.4, Sex.male).word, 'Normal');
    });

    test('sex-specific ranges', () {
      final hb = testByKey('hb')!;
      expect(labStatus(hb, 12.5, Sex.female).level, Level.normal);
      expect(labStatus(hb, 12.5, Sex.male).level, Level.low);
    });
  });

  group('fresh install', () {
    setUp(() => SharedPreferences.setMockInitialValues({'family_health_v1': '{"old":"sample data"}'}));

    test('starts empty, needs setup, and drops the old sample data', () async {
      final s = await AppStore.load();
      expect(s.members, isEmpty);
      expect(s.docs, isEmpty);
      expect(s.meds, isEmpty);
      expect(s.vitals, isEmpty);
      expect(s.isSetUp, isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('family_health_v1'), isNull);
    });

    test('adding people sets colours and check-ups; removing deletes their data', () async {
      final s = await AppStore.load();
      final a = Member(id: 'a', name: 'Ravi', initial: 'R', age: 30, bloodGroup: '', sex: Sex.male, role: Role.admin, color: s.nextColor());
      s.addMember(a);
      final b = Member(id: 'b', name: 'Amma', initial: 'A', age: 55, bloodGroup: 'O+', sex: Sex.female, role: Role.simple, color: s.nextColor(), conditions: ['diabetes']);
      s.addMember(b);
      expect(a.color, isNot(b.color));
      expect(s.checkupsOf('b').map((c) => c.name), contains('Foot check'));
      s.addVital(Vital(id: 'v1', memberId: 'b', type: VitalType.bp, at: DateTime.now(), a: 120, b: 80));
      s.deleteMember('b');
      expect(s.members.length, 1);
      expect(s.vitals, isEmpty);
      expect(s.checkupsOf('b'), isEmpty);
    });

    test('delete everything returns to setup', () async {
      final s = await AppStore.load();
      s.addMember(Member(id: 'a', name: 'Ravi', initial: 'R', age: 30, bloodGroup: '', sex: Sex.male, role: Role.admin, color: s.nextColor()));
      s.setPref((p) => p.setupDone = true);
      expect(s.isSetUp, isTrue);
      s.deleteEverything();
      expect(s.isSetUp, isFalse);
      expect(s.members, isEmpty);
    });
  });

  group('store with sample data', () {
    late AppStore s;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      s = await AppStore.load();
      seedDemoData(s);
    });

    test('insight text is descriptive and matches the brief', () {
      expect(s.insightFor('father', 'hba1c'), 'HbA1c has come down from 8.50 to 6.80 over six years and has been under 7.00 since 2025.');
    });

    test('three reports need review', () {
      expect(s.reviewCount, 3);
    });

    test('September adherence is 174 of 180 doses', () {
      final m = s.adherenceMonth('father', DateTime(2026, 9), now: DateTime(2026, 10, 8, 20));
      final exp = m.values.fold<int>(0, (a, e) => a + e.$1), got = m.values.fold<int>(0, (a, e) => a + e.$2);
      expect(exp, 180);
      expect(got, 174);
    });

    test('taking a dose logs it and uses stock; undo restores it', () {
      final d = s.dosesOn(DateTime.now(), memberId: 'father').firstWhere((d) => d.status != DoseStatus.taken);
      final before = d.med.stock;
      s.takeDose(d);
      final after = s.dosesOn(DateTime.now(), memberId: 'father').firstWhere((x) => x.med.id == d.med.id && x.slot.key == d.slot.key);
      expect(after.status, DoseStatus.taken);
      expect(d.med.stock, before - 1);
      s.undoDose(after);
      expect(d.med.stock, before);
    });

    test('confirming a review moves values into trends', () {
      final apollo = s.docs.firstWhere((d) => d.lab == 'Apollo Clinic' && d.status == DocStatus.needsReview);
      final n = s.resultsOf('father', 'tg').length;
      s.confirmDoc(apollo.id);
      expect(s.resultsOf('father', 'tg').length, n + 1);
      expect(s.doc(apollo.id)!.status, DocStatus.parsed);
    });

    test('data survives a reload', () async {
      s.addVital(Vital(id: 'v-test', memberId: 'father', type: VitalType.weight, at: DateTime.now(), a: 83.5));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final again = await AppStore.load();
      expect(again.vitals.any((v) => v.id == 'v-test'), isTrue);
    });
  });
}
