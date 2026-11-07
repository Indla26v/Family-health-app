import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class AdherenceScreen extends StatefulWidget {
  const AdherenceScreen({super.key, this.memberId});
  final String? memberId;
  @override
  State<AdherenceScreen> createState() => _AdherenceScreenState();
}

class _AdherenceScreenState extends State<AdherenceScreen> {
  String? memberId;
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??= people.any((m) => m.id == widget.memberId) ? widget.memberId : people.first.id;
    final data = s.adherenceMonth(memberId!, month);
    final exp = data.values.fold<int>(0, (a, e) => a + e.$1), got = data.values.fold<int>(0, (a, e) => a + e.$2);
    final pct = exp == 0 ? null : (got * 100 / exp).round();
    final missed = s.missedDoses(memberId!, month);
    final isNow = month.year == DateTime.now().year && month.month == DateTime.now().month;

    // Group missed doses by day.
    final byDay = <int, List<Dose>>{};
    for (final d in missed) {
      byDay.putIfAbsent(d.time.day, () => []).add(d);
    }
    String slotName(Dose d) => d.time.hour < 12 ? 'Morning' : (d.time.hour < 17 ? 'Afternoon' : 'Night');

    return PageBody(
      header: ScreenHeader(title: 'Adherence', back: true, trailing: headerActions(MemberPicker(members: people, selectedId: memberId, onSelect: (id) => setState(() => memberId = id)))),
      children: [
        SurfaceCard(
          child: Column(children: [
            Row(children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
              Expanded(child: Center(child: Text('${monthName(month.month)} ${month.year}', style: AppText.title))),
              IconButton(
                tooltip: 'Next month',
                onPressed: isNow ? null : () => setState(() => month = DateTime(month.year, month.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ]),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: pct == null ? '–' : '$pct%', style: AppText.displayNumber),
              TextSpan(text: exp == 0 ? '  no doses recorded' : '  of $exp doses taken', style: TextStyle(fontSize: 16, color: c.textSecondary)),
            ])),
            const SizedBox(height: 12),
            AdherenceGrid(month: month, data: data),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 8, children: [
              LegendDot(c.okTint, 'All taken'),
              LegendDot(c.warnTint, '1 missed', mark: '!'),
              LegendDot(c.dangerTint, '2+ missed', mark: '×'),
            ]),
          ]),
        ),
        Row(children: [
          const Expanded(child: Text('Missed doses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          Text('${missed.length}', style: AppText.numberLarge),
        ]),
        if (missed.isEmpty)
          SurfaceCard(child: Row(children: [Icon(Icons.check_circle_rounded, color: c.ok), const SizedBox(width: 12), const Expanded(child: Text('No missed doses this month', style: TextStyle(fontSize: 16)))]))
        else
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (final e in byDay.entries) ...[
                if (e.key != byDay.keys.first) const Divider1(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.cancel_rounded, color: c.danger, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.value.map((d) => d.med.label).toSet().join(', '), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text('${e.key} ${monthName(month.month).substring(0, 3)} · ${e.value.map(slotName).toSet().join(' + ')}${e.value.any((d) => d.status == DoseStatus.skipped) ? ' · some skipped' : ''}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
      ],
    );
  }
}
