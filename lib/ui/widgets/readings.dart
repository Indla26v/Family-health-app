import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/reading_metric.dart';
import '../../data/store.dart';
import 'common.dart';
import 'metric_card.dart';

StatusInfo weightStatus(List<Vital> w) {
  if (w.length < 2) return const StatusInfo(Level.none, 'Steady');
  final d = w.last.a - w[w.length - 2].a;
  if (d.abs() < .5) return const StatusInfo(Level.none, 'Steady');
  return StatusInfo(Level.none, '${d > 0 ? 'Up' : 'Down'} ${d.abs().toStringAsFixed(2)} kg');
}

List<Widget> readingCards(AppStore store, Member member, ValueChanged<ReadingMetric> onTrend) => [
  for (final metric in ReadingMetric.values)
    _readingCard(metric, store.readingsFor(member.id, metric), () => onTrend(metric)),
];

Widget _readingCard(ReadingMetric metric, List<Vital> rows, VoidCallback onTap) {
  final latest = rows.lastOrNull;
  return MetricCard(
    icon: metric.icon,
    label: metric.label,
    empty: latest == null,
    value: latest == null ? '' : metric.format(latest),
    unit: metric.unit,
    status: latest == null ? null : metric == ReadingMetric.weight ? weightStatus(rows) : VitalRanges.ofVital(latest),
    spark: rows.skip(rows.length > 7 ? rows.length - 7 : 0).map((row) => row.a).toList(),
    when: latest == null ? '' : ago(latest.at),
    onTap: onTap,
  );
}
