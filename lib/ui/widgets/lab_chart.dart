import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../screens/doc_viewer.dart';
import 'charts.dart';

ChartBand? bandFor(TestDef t, Sex sex) {
  final lo = t.lowFor(sex), hi = t.highFor(sex);
  if (lo == null && hi == null) return null;
  return ChartBand(lo, hi, 'Normal ${t.refText(sex)}');
}

List<ChartPoint> labPoints(AppStore s, Member m, TestDef t) => [
      for (final r in s.resultsOf(m.id, t.key))
        ChartPoint(r.date, r.value, lab: r.lab, docId: r.docId, outside: labStatus(t, r.value, m.sex).level != Level.normal, label: fmtVal(t, r.value)),
    ];

String labSummary(AppStore s, Member m, TestDef t) {
  final r = s.resultsOf(m.id, t.key);
  if (r.isEmpty) return '${t.name}: no results yet.';
  return '${t.name} went from ${fmtVal(t, r.first.value)} in ${r.first.date.year} to ${fmtVal(t, r.last.value)} ${t.unit} in ${r.last.date.year}. ${s.insightFor(m.id, t.key) ?? ''}';
}

/// A single lab test over time, with reference band, optional target, and
/// tap-to-open source report.
class LabTrendChart extends StatelessWidget {
  const LabTrendChart({super.key, required this.store, required this.member, required this.test, required this.color});
  final AppStore store;
  final Member member;
  final TestDef test;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return TrendChart(
      series: [ChartSeries(labPoints(store, member, test), color, name: test.name)],
      band: bandFor(test, member.sex),
      targetLine: test.target,
      targetLabel: test.target == null ? null : 'Target < ${fmtVal(test, test.target!)}',
      unit: test.unit,
      decimals: 2, // lab values always show two decimals
      summary: labSummary(store, member, test),
      onViewReport: (p) => openDocument(context, p.docId!),
    );
  }
}
