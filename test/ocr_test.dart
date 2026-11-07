import 'dart:math';
import 'dart:ui';

import 'package:family_health/services/ocr.dart';
import 'package:family_health/services/parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recognised cell at (x, y) on a page tilted by [tilt] radians.
OcrLine cell(String text, double x, double y, {double w = 120, double tilt = 0}) {
  final dy = x * tan(tilt);
  return OcrLine(text, Rect.fromLTWH(x, y + dy, w, 30), tilt);
}

void main() {
  test('table cells read separately are put back into rows', () {
    final text = rowsOf([
      cell('HAEMOGLOBIN (HB)', 40, 400, w: 300),
      cell('12.3', 520, 404, w: 60),
      cell('g/dl', 640, 398, w: 60),
      cell('12.0 - 15.0', 760, 402, w: 160),
      cell('FASTING PLASMA GLUCOSE', 40, 470, w: 380),
      cell('128', 520, 472, w: 60),
      cell('mg/dl', 640, 468, w: 70),
      cell('70 - 100', 760, 471, w: 140),
    ]);
    expect(text.split('\n'), ['HAEMOGLOBIN (HB)  12.3  g/dl  12.0 - 15.0', 'FASTING PLASMA GLUCOSE  128  mg/dl  70 - 100']);
    final r = ReportParser.parse(text);
    expect(r.tests.firstWhere((t) => t.testKey == 'hb').value, 12.3);
    expect(r.tests.firstWhere((t) => t.testKey == 'fbs').value, 128);
  });

  test('a slightly tilted photo still lines up', () {
    const tilt = 0.035; // about 2 degrees: the right-hand cells sit ~30 px lower
    final text = rowsOf([
      cell('HBA1c RESULT', 40, 400, w: 300, tilt: tilt),
      cell('8.2', 900, 400, w: 60, tilt: tilt),
      cell('TSH', 40, 450, w: 300, tilt: tilt),
      cell('2.26', 900, 450, w: 60, tilt: tilt),
    ]);
    expect(text.split('\n'), ['HBA1c RESULT  8.2', 'TSH  2.26']);
  });

  test('the Vitamin D page from a photo reads its value, date and patient', () {
    final text = rowsOf([
      cell('Patient Name', 40, 160, w: 140),
      cell(': Mrs. I.PRATHYUSHA', 360, 162, w: 220),
      cell('Collected', 760, 238, w: 90),
      cell(': 2026-10-26 08:54', 880, 240, w: 160),
      cell('25 HYDROXY VITAMIN D', 580, 388, w: 260),
      cell('Sample Type : SERUM', 230, 405, w: 200),
      cell('25 HYDROXY VITAMIN D', 236, 430, w: 230),
      cell('25.69', 600, 442, w: 60),
      cell('ng/ml', 712, 446, w: 60),
      cell('30 - 70', 870, 451, w: 80),
      cell('CLIA', 1060, 457, w: 50),
      cell('Deficiency (serious deficient)', 224, 520, w: 260),
      cell('< 20 ng/ml', 642, 533, w: 120),
    ]);
    final r = ReportParser.parse(text);
    final d = r.tests.singleWhere((t) => t.testKey == 'vitd');
    expect((d.value, d.refText), (25.69, '30 - 70'));
    expect(r.date, DateTime(2026, 10, 26));
    expect(r.patientName, contains('PRATHYUSHA'));
  });

  test('text as your phone read the HbA1c and lipid pages', () {
    final r = ReportParser.parse([
      'Ref Doctor  :SELE  Registration  :2026-10-25 09:53',
      'HBA1C',
      'HBAlc RESULT  8.2  Normal Glucose tolerance  HPLC',
      'HDLCHOLESTEROL  32  mg/dl  >40  Enzymatic',
      'LDLCHOLESTEROL  664  mg/dl  See Refer Table below  Enzymatic Selective',
      'NON HDL CHOLESTEROL  93  mg/dl  <130  Calculated',
      'TSH  2.26  ulU/ml  0.3-5.6  CLIA',
    ].join('\n'));
    double? v(String k) => r.tests.where((t) => t.testKey == k).firstOrNull?.value;
    expect(v('hba1c'), 8.2);
    expect(v('hdl'), 32); // not the Non-HDL 93
    expect(v('ldl'), 664); // the photo lost the decimal point: photo readings always go to review
    expect(v('tsh'), 2.26);
  });
}
