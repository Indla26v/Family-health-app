import 'dart:ui';

import 'package:family_health/services/ocr.dart';
import 'package:family_health/services/parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cell as ML Kit reported it on a real photo: box only, slant given as level.
OcrLine box(String text, double l, double t, double r, double b) => OcrLine(text, Rect.fromLTRB(l, t, r, b), 0);

void main() {
  test('a tilted thyroid table keeps each value with its own test', () {
    // Positions from a photographed SGS report: the page slopes ~1.6° down to the
    // right, so each value sits about half a row lower than its test name.
    final text = rowsOf([
      box('THYROID PROFILE (T3,T4,TSH)', 343, 990, 760, 1009),
      box('Sample Type : SERUM', 343, 1022, 610, 1041),
      box('T3', 343, 1058, 369, 1077),
      box('0.83', 904, 1074, 943, 1092),
      box('ng/m', 1055, 1082, 1102, 1102),
      box('0.60 -1.78', 1250, 1086, 1400, 1105),
      box('CLIA', 1540, 1092, 1590, 1111),
      box('T4', 343, 1094, 368, 1112),
      box('9,03', 905, 1109, 942, 1128),
      box('ug/dl', 1059, 1114, 1100, 1135),
      box('4,82 - 15.65', 1250, 1121, 1420, 1140),
      box('CLIA', 1540, 1127, 1590, 1146),
      box('TSH', 344, 1130, 393, 1149),
      box('2.26', 905, 1143, 943, 1161),
      box('ulU/ml', 1045, 1147, 1117, 1166),
      box('0.3-5.6', 1250, 1155, 1350, 1174),
      box('CLIA', 1540, 1162, 1590, 1181),
    ]);
    final rows = text.split('\n');
    expect(rows, contains('T3  0.83  ng/m  0.60 -1.78  CLIA'));
    expect(rows, contains('T4  9,03  ug/dl  4,82 - 15.65  CLIA'));
    expect(rows, contains('TSH  2.26  ulU/ml  0.3-5.6  CLIA'));
    final r = ReportParser.parse(text);
    double? v(String k) => r.tests.where((t) => t.testKey == k).firstOrNull?.value;
    expect((v('t3'), v('t4'), v('tsh')), (0.83, 9.03, 2.26));
  });
}
