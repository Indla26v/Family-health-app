import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/health_reading.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import '../widgets/lab_chart.dart';
import 'doc_viewer.dart';
import 'diabetes_detail.dart';
import 'manual_entry.dart';
import 'log_reading.dart';
import 'reading_history.dart';
import 'today.dart';

/// Any single test (e.g. LDL): full chart, reference band, and every result
/// with lab + date, each linking to the source report.
class TestTrendScreen extends StatelessWidget {
  const TestTrendScreen({super.key, required this.memberId, required this.testKey});
  final String memberId, testKey;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = s.member(memberId)!;
    final t = testByKey(testKey)!;
    final r = s.healthReadingsOf(m.id, t.key);
    final glucose = t.key == 'fbs' || t.key == 'ppbs';
    final last = r.isEmpty ? null : r.last;
    final st = last == null ? null : healthReadingStatus(last, t, m.sex);
    final insight = glucose ? null : s.insightFor(m.id, t.key);
    final cond = conditionDefs.where((d) => d.keyTest == t.key).firstOrNull;

    return PageBody(
      header: ScreenHeader(
        title: t.name,
        subtitle: '${m.name} · ${t.unit}',
        back: true,
        trailing: IconButton(tooltip: glucose ? 'Log sugar' : 'Add a value by hand', onPressed: () => pushPage(context, glucose
          ? LogReadingScreen(memberId: m.id, mode: VitalType.sugar, afterMeal: t.key == 'ppbs')
          : ManualEntryScreen(memberId: m.id, testKey: t.key)), icon: const Icon(Icons.add_circle_outline_rounded)),
      ),
      children: [
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (last == null)
              Text('No results yet.', style: TextStyle(fontSize: 15, color: c.textSecondary))
            else ...[
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Latest · ${fmtDate(last.date)}${last.isHome ? ' · ${fmtTime(last.date)}' : ''}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
                    Text(last.source, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                    Text.rich(TextSpan(children: [TextSpan(text: fmtVal(t, last.value), style: AppText.displayNumber), TextSpan(text: ' ${t.unit}', style: TextStyle(fontSize: 16, color: c.textSecondary))])),
                  ]),
                ),
                StatusPill.info(st!),
              ]),
              const SizedBox(height: 12),
              LabTrendChart(store: s, member: m, test: t, color: m.color),
              if (insight != null) ...[const SizedBox(height: 8), Text(insight, style: TextStyle(fontSize: 15, height: 22 / 16, color: c.textSecondary))],
            ],
          ]),
        ),
        if (r.isNotEmpty)
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('All results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                Text('${r.length} ${r.length == 1 ? 'reading' : 'readings'}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              ]),
              const SizedBox(height: 8),
              for (final x in r.reversed) ...[
                const Divider1(),
                InkWell(
                  onTap: () => x.docId != null ? openDocument(context, x.docId!) : pushPage(context, ReadingHistoryScreen(memberId: m.id, type: VitalType.sugar, afterMeal: t.key == 'ppbs')),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        SizedBox(width: 80, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                          child: Text(fmtVal(t, x.value), maxLines: 1, style: AppText.numberLarge.copyWith(fontSize: 21)))),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(x.source, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                            Text('${fmtDate(x.date)}${x.isHome ? ' · ${fmtTime(x.date)}' : ''}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                          ]),
                        ),
                        StatusPill.info(healthReadingStatus(x, t, m.sex)),
                        const SizedBox(width: 8),
                        Semantics(label: x.isHome ? 'View reading history' : 'View source report', child: Icon(x.isHome ? Icons.history_rounded : Icons.description_rounded, size: 22, color: c.accent)),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        if (cond != null && cond.id != 'diabetes') ConditionExtras(store: s, member: m, condition: cond.id, checkTitle: 'Related check-ups'),
      ],
    );
  }
}
