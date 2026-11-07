import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'diabetes_detail.dart';
import 'log_reading.dart';
import 'today.dart';

/// Blood pressure: dual-line chart (systolic + diastolic) with target bands,
/// recent readings, linked medicines.
class BpDetailScreen extends StatelessWidget {
  const BpDetailScreen({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = s.member(memberId)!;
    final v = s.vitalsOf(m.id, VitalType.bp);
    final last = v.isEmpty ? null : v.last;

    List<ChartPoint> pts(double Function(Vital) f, bool sys) => [
          for (final x in v)
            ChartPoint(x.at, f(x), outside: sys ? (x.a >= 130 || x.a < 90) : (x.b >= 85 || x.b < 60), label: '${x.a.round()}/${x.b.round()}'),
        ];

    DateTime? cut(Period p) {
      final n = DateTime.now();
      return switch (p) { Period.m3 => n.subtract(const Duration(days: 7)), Period.m6 => n.subtract(const Duration(days: 30)), Period.y1 => n.subtract(const Duration(days: 90)), Period.all => null };
    }

    String label(Period p) => switch (p) { Period.m3 => '7D', Period.m6 => '30D', Period.y1 => '90D', Period.all => 'All' };

    return PageBody(
      header: ScreenHeader(title: 'Blood pressure', subtitle: m.name, back: true, trailing: const SettingsButton()),
      bottom: BigButton(label: 'Log BP', icon: Icons.add_rounded, onTap: () => pushPage(context, LogReadingScreen(memberId: m.id, mode: VitalType.bp))),
      children: [
        if (last == null)
          const EmptyState(icon: Icons.monitor_heart_rounded, message: 'No blood pressure readings yet', detail: 'Log a reading to start the trend.')
        else ...[
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Latest · ${ago(last.at)}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
                    Text.rich(TextSpan(children: [TextSpan(text: '${last.a.round()}/${last.b.round()}', style: AppText.displayNumber), TextSpan(text: ' mmHg', style: TextStyle(fontSize: 16, color: c.textSecondary))])),
                  ]),
                ),
                StatusPill.info(VitalRanges.ofVital(last)),
              ]),
              const SizedBox(height: 12),
              TrendChart(
                unit: 'mmHg',
                decimals: 0,
                initial: Period.y1,
                periods: const [Period.m3, Period.m6, Period.y1, Period.all],
                periodLabelOf: label,
                cutoffOf: cut,
                band: ChartBand(90, 130, ''),
                moreBands: [ChartBand(60, 85, '')],
                summary: 'Blood pressure readings. Latest ${last.a.round()} over ${last.b.round()} mmHg, ${VitalRanges.ofVital(last).word}.',
                series: [
                  ChartSeries(pts((x) => x.a, true), m.color, name: 'Systolic'),
                  ChartSeries(pts((x) => x.b, false), c.info, name: 'Diastolic'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 18, runSpacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 4, color: m.color), const SizedBox(width: 6), const Text('Systolic (top)', style: TextStyle(fontSize: 14))]),
                Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 4, color: c.info), const SizedBox(width: 6), const Text('Diastolic (bottom)', style: TextStyle(fontSize: 14))]),
              ]),
              const SizedBox(height: 4),
              Text('Shaded: usual range (90–130 / 60–85).', style: TextStyle(fontSize: 14, color: c.textSecondary)),
            ]),
          ),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: Text('Recent readings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              const SizedBox(height: 8),
              for (final x in v.reversed.take(10)) ...[
                const Divider1(),
                SizedBox(
                  height: 60,
                  child: Row(children: [
                    SizedBox(width: 96, child: Text('${x.a.round()}/${x.b.round()}', style: AppText.numberLarge.copyWith(fontSize: 19))),
                    Expanded(child: Text('${fmtDay(x.at)}, ${fmtTime(x.at)}${x.pulse > 0 ? ' · pulse ${x.pulse.round()}' : ''}', style: TextStyle(fontSize: 14, color: c.textSecondary))),
                    StatusPill.info(VitalRanges.ofVital(x)),
                  ]),
                ),
              ],
            ]),
          ),
        ],
        ConditionExtras(store: s, member: m, condition: 'bp', checkTitle: 'Related check-ups'),
      ],
    );
  }
}
