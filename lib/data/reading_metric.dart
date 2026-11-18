import 'package:flutter/material.dart';

import 'models.dart';

enum ReadingMetric {
  bp(VitalType.bp, 'Blood pressure', 'mmHg', Icons.monitor_heart_rounded),
  fasting(
    VitalType.sugar,
    'Fasting glucose',
    'mg/dL',
    Icons.water_drop_rounded,
    afterMeal: false,
  ),
  post(
    VitalType.sugar,
    'Post-meal glucose',
    'mg/dL',
    Icons.water_drop_rounded,
    afterMeal: true,
  ),
  weight(
    VitalType.weight,
    'Weight',
    'kg',
    Icons.monitor_weight_rounded,
    decimals: 2,
  ),
  oxygen(VitalType.spo2, 'Oxygen (SpO2)', '%', Icons.air_rounded);

  const ReadingMetric(
    this.type,
    this.label,
    this.unit,
    this.icon, {
    this.afterMeal,
    this.decimals = 0,
  });
  final VitalType type;
  final String label, unit;
  final IconData icon;
  final bool? afterMeal;
  final int decimals;

  static ReadingMetric of(VitalType type, {bool afterMeal = false}) =>
      values.firstWhere(
        (metric) =>
            metric.type == type &&
            (metric.afterMeal == null || metric.afterMeal == afterMeal),
      );

  String format(Vital reading) => type == VitalType.bp
      ? '${reading.a.round()}/${reading.b.round()}'
      : reading.a.toStringAsFixed(decimals);
}
