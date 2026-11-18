import 'package:flutter/material.dart';

import '../../data/reading_metric.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'log_reading.dart';
import 'reading_history.dart';
import 'today.dart';

class VitalTrendScreen extends StatelessWidget {
  const VitalTrendScreen({
    super.key,
    required this.memberId,
    required this.metric,
  });

  final String memberId;
  final ReadingMetric metric;

  @override
  Widget build(BuildContext context) {
    final store = watchStore(context);
    final member = store.member(memberId);
    final readings = store.readingsFor(memberId, metric);
    final latest = readings.lastOrNull;
    return PageBody(
      header: ScreenHeader(
        title: metric.label,
        subtitle: member?.name,
        back: true,
      ),
      bottom: BigButton(
        label: 'Log reading',
        icon: Icons.add_rounded,
        onTap: () => pushPage(
          context,
          LogReadingScreen(memberId: memberId, mode: metric.type),
        ),
      ),
      children: [
        if (latest == null)
          EmptyState(
            icon: metric.icon,
            message: 'No readings yet',
            detail: 'Log a reading to start your graph.',
          )
        else
          SurfaceCard(
            child: TrendChart(
              series: [
                ChartSeries(
                  [
                    for (final reading in readings)
                      ChartPoint(reading.at, reading.a),
                  ],
                  member?.color ?? Theme.of(context).colorScheme.primary,
                  name: metric.label,
                ),
              ],
              unit: metric.unit,
              decimals: metric.decimals,
              summary:
                  '${metric.label}. Latest ${metric.format(latest)} ${metric.unit}.',
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextLink(
            'Reading history',
            icon: Icons.history_rounded,
            onTap: () => pushPage(
              context,
              ReadingHistoryScreen(memberId: memberId, type: metric.type),
            ),
          ),
        ),
      ],
    );
  }
}

class WeightTrendScreen extends VitalTrendScreen {
  const WeightTrendScreen({super.key, required super.memberId})
    : super(metric: ReadingMetric.weight);
}
