import 'package:flutter/material.dart';

import '../../core/features.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/lab_chart.dart';
import 'doc_viewer.dart';
import 'health.dart';
import 'medicines.dart';
import 'test_trend.dart';
import 'today.dart';
import 'upload.dart';

/// Medicines linked to a condition + related check-ups (shared by detail pages).
class ConditionExtras extends StatelessWidget {
  const ConditionExtras({super.key, required this.store, required this.member, required this.condition, required this.checkTitle});
  final AppStore store;
  final Member member;
  final String condition;
  final String checkTitle;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meds = store.medsOf(member.id).where((m) => m.forCondition == condition).toList();
    final checks = store.checkupsOf(member.id).where((x) => x.condition == condition).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (kMedicinesEnabled) ...[
      SectionTitle('Current medicines', action: 'Manage', onAction: () => pushPage(context, MedicinesScreen(memberId: member.id))),
      const SizedBox(height: 8),
      SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: meds.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No medicines linked yet.', style: TextStyle(fontSize: 15, color: c.textSecondary)))
            : Column(children: [
                for (var i = 0; i < meds.length; i++) ...[
                  if (i > 0) const Divider1(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      PillThumb(meds[i], color: member.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(meds[i].label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          Text('${meds[i].times.map((t) => t.hour < 12 ? 'Morning' : (t.hour < 17 ? 'Afternoon' : 'Night')).join(' + ')}${meds[i].food == Food.any ? '' : ' · ${foodText(meds[i].food)}'}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                        ]),
                      ),
                    ]),
                  ),
                ],
              ]),
      ),
      ],
      if (kCheckupsEnabled && checks.isNotEmpty) ...[
        if (kMedicinesEnabled) const SizedBox(height: 16),
        SectionTitle(checkTitle),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            for (var i = 0; i < checks.length; i++) ...[
              if (i > 0) const Divider1(),
              CheckupRow(checkup: checks[i]),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class DiabetesDetailScreen extends StatelessWidget {
  const DiabetesDetailScreen({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = s.member(memberId)!;
    final hba = testByKey('hba1c')!;
    final r = s.resultsOf(m.id, 'hba1c');
    final last = r.isEmpty ? null : r.last;

    // Monthly averages of home readings.
    List<ChartPoint> monthly(bool after) {
      final byMonth = <DateTime, List<double>>{};
      for (final v in s.vitalsOf(m.id, VitalType.sugar).where((v) => v.afterMeal == after)) {
        byMonth.putIfAbsent(DateTime(v.at.year, v.at.month), () => []).add(v.a);
      }
      final keys = byMonth.keys.toList()..sort();
      return [for (final k in keys) ChartPoint(DateTime(k.year, k.month, 15), byMonth[k]!.reduce((a, b) => a + b) / byMonth[k]!.length, label: (byMonth[k]!.reduce((a, b) => a + b) / byMonth[k]!.length).round().toString())];
    }

    final fasting = monthly(false), post = monthly(true);
    final fbs = testByKey('fbs')!, ppbs = testByKey('ppbs')!;
    final hasLabSugar = s.resultsOf(m.id, 'fbs').isNotEmpty || s.resultsOf(m.id, 'ppbs').isNotEmpty;
    final insight = s.insightFor(m.id, 'hba1c');
    final st = last == null ? null : labStatus(hba, last.value, m.sex);

    return PageBody(
      header: ScreenHeader(title: 'Diabetes', subtitle: m.name, back: true, trailing: const SettingsButton()),
      children: [
        if (last == null)
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('No HbA1c report yet', style: AppText.title),
              const SizedBox(height: 4),
              Text('Upload a report to see the trend.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
              TextLink('Upload report', icon: Icons.upload_rounded, onTap: () => pushPage(context, UploadScreen(memberId: m.id))),
            ]),
          )
        else
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('HbA1c · last ${((last.date.difference(r.first.date).inDays) / 365.25).ceil().clamp(1, 99)} years', style: TextStyle(fontSize: 15, color: c.textSecondary)),
                    Text.rich(TextSpan(children: [TextSpan(text: fmtVal(hba, last.value), style: AppText.displayNumber), TextSpan(text: ' %', style: TextStyle(fontSize: 16, color: c.textSecondary))])),
                  ]),
                ),
                StatusPill.info(st!),
              ]),
              const SizedBox(height: 12),
              LabTrendChart(store: s, member: m, test: hba, color: m.color),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 12, color: c.danger), const SizedBox(width: 6), const Text('Above target', style: TextStyle(fontSize: 14))]),
                Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 12, color: m.color), const SizedBox(width: 6), const Text('Under target', style: TextStyle(fontSize: 14))]),
              ]),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: TextLink('All HbA1c results', onTap: () => pushPage(context, TestTrendScreen(memberId: m.id, testKey: 'hba1c')))),
            ]),
          ),
        if (insight != null) InsightCard(text: insight),
        if (fasting.length + post.length > 1)
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Daily sugar', style: AppText.title),
              Text('Monthly average of home readings (mg/dL)', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              const SizedBox(height: 12),
              TrendChart(
                showPeriods: false,
                unit: 'mg/dL',
                decimals: 0,
                summary: 'Monthly average of home sugar readings. Before breakfast ${fasting.isEmpty ? 'none' : fasting.last.label}, after meals ${post.isEmpty ? 'none' : post.last.label}.',
                series: [
                  ChartSeries(fasting, m.color, name: 'Before breakfast', colourOutside: false),
                  ChartSeries(post, c.info, name: 'After meals', colourOutside: false),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 18, runSpacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 4, color: m.color), const SizedBox(width: 6), Text('Before breakfast · ${fasting.isEmpty ? '–' : fasting.last.label}', style: const TextStyle(fontSize: 14))]),
                Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 4, color: c.info), const SizedBox(width: 6), Text('After meals · ${post.isEmpty ? '–' : post.last.label}', style: const TextStyle(fontSize: 14))]),
              ]),
            ]),
          ),
        if (hasLabSugar)
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lab sugar tests', style: AppText.title),
              Text('FBS and PPBS from lab reports', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              const SizedBox(height: 12),
              TrendChart(
                showPeriods: false,
                unit: 'mg/dL',
                decimals: 2,
                band: ChartBand(fbs.low, fbs.high, 'Fasting normal 70–100'),
                summary: labSummary(s, m, fbs),
                series: [
                  ChartSeries(labPoints(s, m, fbs), m.color, name: 'FBS'),
                  ChartSeries(labPoints(s, m, ppbs), c.info, name: 'PPBS', colourOutside: false),
                ],
                onViewReport: (p) => openDocument(context, p.docId!),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 18, runSpacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 4, color: m.color), const SizedBox(width: 6), const Text('Fasting (FBS)', style: TextStyle(fontSize: 14))]),
                Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 4, color: c.info), const SizedBox(width: 6), const Text('After meal (PPBS)', style: TextStyle(fontSize: 14))]),
              ]),
            ]),
          ),
        ConditionExtras(store: s, member: m, condition: 'diabetes', checkTitle: 'Related check-ups'),
      ],
    );
  }
}
