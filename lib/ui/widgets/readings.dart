import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import 'common.dart';
import 'metric_card.dart';

StatusInfo weightStatus(List<Vital> w) {
  if (w.length < 2) return const StatusInfo(Level.none, 'Steady');
  final d = w.last.a - w[w.length - 2].a;
  if (d.abs() < .5) return const StatusInfo(Level.none, 'Steady');
  return StatusInfo(Level.none, '${d > 0 ? 'Up' : 'Down'} ${d.abs().toStringAsFixed(2)} kg');
}

/// BP, sugar-before-breakfast and weight cards for one member.
List<Widget> readingCards(BuildContext context, AppStore s, Member m, {required VoidCallback onLog, VoidCallback? onSugar}) {
  final bp = s.vitalsOf(m.id, VitalType.bp);
  final sugar = s.vitalsOf(m.id, VitalType.sugar).where((v) => !v.afterMeal).toList();
  final weight = s.vitalsOf(m.id, VitalType.weight);
  List<double> tail(List<Vital> l, [double Function(Vital)? f]) => l.skip(l.length > 7 ? l.length - 7 : 0).map(f ?? (v) => v.a).toList();
  return [
    MetricCard(
      icon: Icons.monitor_heart_rounded,
      label: 'Blood pressure',
      empty: bp.isEmpty,
      value: bp.isEmpty ? '' : '${bp.last.a.round()}/${bp.last.b.round()}',
      unit: 'mmHg',
      status: bp.isEmpty ? null : VitalRanges.ofVital(bp.last),
      spark: tail(bp),
      when: bp.isEmpty ? '' : ago(bp.last.at),
      onTap: onLog,
    ),
    MetricCard(
      icon: Icons.water_drop_rounded,
      label: 'Sugar before breakfast',
      empty: sugar.isEmpty,
      value: sugar.isEmpty ? '' : sugar.last.a.round().toString(),
      unit: 'mg/dL',
      status: sugar.isEmpty ? null : VitalRanges.ofVital(sugar.last),
      spark: tail(sugar),
      when: sugar.isEmpty ? '' : ago(sugar.last.at),
      onTap: onSugar ?? onLog,
    ),
    MetricCard(
      icon: Icons.monitor_weight_rounded,
      label: 'Weight',
      empty: weight.isEmpty,
      value: weight.isEmpty ? '' : weight.last.a.toStringAsFixed(2),
      unit: 'kg',
      status: weight.isEmpty ? null : weightStatus(weight),
      spark: tail(weight),
      when: weight.isEmpty ? '' : ago(weight.last.at),
      onTap: onLog,
    ),
  ];
}
