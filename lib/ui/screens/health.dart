import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../data/card_order.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/trend_card.dart';
import 'arrange_cards.dart';
import 'bp_detail.dart';
import 'diabetes_detail.dart';
import 'log_reading.dart';
import 'test_trend.dart';
import 'today.dart';
import 'upload.dart';

/// Health overview for one member: condition cards, every test as a graph tile, check-ups.
/// The display period: from [from] (inclusive) up to [to] (exclusive); null ends are open.
class Span {
  const Span([this.from, this.to]);
  final DateTime? from, to;
  bool get isAll => from == null && to == null;
  bool has(DateTime d) => (from == null || !d.isBefore(from!)) && (to == null || d.isBefore(to!));

  /// 'all', '1y' (the last 12 months) or a calendar year such as '2021'.
  static Span of(String key) {
    final now = DateTime.now();
    final y = int.tryParse(key);
    if (y != null) return Span(DateTime(y), DateTime(y + 1));
    if (key == '1y') return Span(DateTime(now.year - 1, now.month, now.day));
    return const Span();
  }
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String period = 'all';

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final people = s.visibleMembers;
    // The person picked in the header, else whoever uses this phone.
    final m = people.firstWhere((x) => x.id == s.selectedId, orElse: () => people.firstWhere((x) => x.id == s.currentUser.id, orElse: () => people.first));
    // Years with results, newest first; each can be picked on its own.
    final years = ({for (final l in s.labs) if (l.memberId == m.id && l.confirmed) l.date.year}.toList()..sort((a, b) => b - a)).map((y) => '$y').toList();
    final key = period == '1y' || years.contains(period) ? period : 'all';
    final from = Span.of(key);
    final conds = byUserOrder(m.conditions.map(conditionById), (c) => 'cond:${c.id}', (c) => c.en, s.prefs.healthOrder);
    final checks = s.checkupsOf(m.id);

    return Column(children: [
      ScreenHeader(title: tr('Health'), big: true, trailing: headerActions(MemberPicker(members: people, selectedId: m.id, onSelect: s.selectMember))),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(kSide, 8, kSide, 32), children: staggered([
          if (conds.isEmpty && !s.labs.any((l) => l.memberId == m.id && l.confirmed))
            SurfaceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('No results yet for ${m.name}', style: AppText.title),
                const SizedBox(height: 12),
                BigButton(label: 'Upload a report', icon: Icons.upload_rounded, onTap: () => pushPage(context, UploadScreen(memberId: m.id))),
              ]),
            ),
          _PeriodSwitch(options: [('all', 'All time'), ('1y', 'Last 12 months'), for (final y in years) (y, y)], value: key, onChanged: (v) => setState(() => period = v)),
          const SizedBox(height: 4),
          if (conds.isNotEmpty) CardColumn(children: [for (final cd in conds) _ConditionCard(store: s, member: m, def: cd, from: from)]),
          _AllTests(store: s, member: m, from: from, skip: {for (final cd in conds) if (cd.keyTest != null && s.resultsOf(m.id, cd.keyTest!).isNotEmpty) cd.keyTest!}),
          if (kCheckupsEnabled) ...[
          const SizedBox(height: 4),
          const SectionTitle('Check-ups'),
          const SizedBox(height: 8),
          if (checks.isEmpty)
            SurfaceCard(child: Text('No check-ups listed.', style: TextStyle(fontSize: 15, color: context.c.textSecondary)))
          else
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
        ])),
      ),
    ]);
  }
}

/// Status of a check-up: Due now / Done / due month.
({String label, String tone, IconData? icon}) checkupState(Checkup c) {
  final now = DateTime.now();
  if (c.last == null) return (label: 'Due now', tone: 'warn', icon: null);
  if (!c.due!.isAfter(now)) return (label: 'Due now', tone: 'warn', icon: null);
  if (now.difference(c.last!).inDays <= 60) return (label: 'Done', tone: 'ok', icon: null);
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return (label: '${mo[c.due!.month - 1]} ${c.due!.year}', tone: 'info', icon: Icons.info_rounded);
}

class CheckupRow extends StatelessWidget {
  const CheckupRow({super.key, required this.checkup});
  final Checkup checkup;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = checkupState(checkup);
    return InkWell(
      onTap: () async {
        final s = readStore(context);
        final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now(), helpText: 'When was ${checkup.name} done?');
        if (d != null) s.markCheckupDone(checkup, d);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(checkup.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(checkup.last == null ? 'Not recorded yet' : 'Last: ${fmtDate(checkup.last!)}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              ]),
            ),
            StatusPill(label: st.label, tone: st.tone, icon: st.icon),
          ]),
        ),
      ),
    );
  }
}

class _ConditionCard extends StatelessWidget {
  const _ConditionCard({required this.store, required this.member, required this.def, this.from = const Span()});
  final AppStore store;
  final Member member;
  final ConditionDef def;

  /// Show only results on or after this day (null = all time).
  final Span from;

  void _open(BuildContext context) {
    switch (def.id) {
      case 'diabetes':
        pushPage(context, DiabetesDetailScreen(memberId: member.id));
      case 'bp':
        pushPage(context, BpDetailScreen(memberId: member.id));
      default:
        if (def.keyTest != null && store.latestResult(member.id, def.keyTest!) != null) {
          pushPage(context, TestTrendScreen(memberId: member.id, testKey: def.keyTest!));
        } else {
          pushPage(context, UploadScreen(memberId: member.id));
        }
    }
  }

  /// No data yet: one compact row.
  Widget _empty(BuildContext context, String title, String hint, String action, VoidCallback onTap) {
    final c = context.c;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      semanticLabel: '$title. $hint. $action',
      child: ExcludeSemantics(
        child: Row(children: [
          Icon(def.icon, size: 18, color: c.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$title  ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              TextSpan(text: hint, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            ])),
          ),
          TextLink(action, onTap: onTap),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = tr(def.en);
    if (def.id == 'bp') {
      final all = store.vitalsOf(member.id, VitalType.bp).where((x) => from.has(x.at)).toList();
      if (all.isEmpty) return _empty(context, title, from.isAll ? 'No readings yet' : 'No readings in this period', 'Log', () => pushPage(context, LogReadingScreen(memberId: member.id)));
      final v = all.skip(all.length > 20 ? all.length - 20 : 0).toList();
      final last = v.last;
      return TrendCard(
        title: title,
        icon: def.icon,
        unit: 'mmHg',
        status: VitalRanges.ofVital(last),
        low: 90,
        high: 130,
        points: [
          for (final x in v) TrendPoint(date: x.at, value: x.a, label: '${x.a.round()}/${x.b.round()}', outside: const [Level.high, Level.low].contains(VitalRanges.ofVital(x).level)),
        ],
        onTap: () => _open(context),
      );
    }
    final key = def.keyTest;
    final t = key == null ? null : testByKey(key);
    final r = key == null ? <LabResult>[] : inPeriod(store.resultsOf(member.id, key), from);
    if (t == null || r.isEmpty) return _empty(context, title, from.isAll ? def.emptyHint : 'No results in this period', 'Add report', () => pushPage(context, UploadScreen(memberId: member.id)));
    return labTrendCard(context, store, member, t, title: '$title · ${t.key == 'hba1c' ? 'HbA1c' : t.name}', icon: def.icon, from: from, onTap: () => _open(context));
  }
}

/// Results dated inside [span] (all of them when null).
List<LabResult> inPeriod(List<LabResult> r, Span? span) => span == null || span.isAll ? r : r.where((x) => span.has(x.date)).toList();

/// The display period as a row of pills (scrolls sideways when there are many years).
class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.options, required this.value, required this.onChanged});
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(999)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, label) in options)
            Semantics(
              button: true,
              selected: k == value,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: kEaseOut,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: k == value ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: k == value ? [BoxShadow(color: c.shadow, blurRadius: 6, offset: const Offset(0, 2))] : null,
                  ),
                  child: Text(label, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: k == value ? FontWeight.w700 : FontWeight.w500, color: k == value ? c.text : c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A lab test as a [TrendCard]: every confirmed result (since [from]), normal range
/// shaded; tap it for the full history and each result's report.
Widget labTrendCard(BuildContext context, AppStore store, Member member, TestDef t, {String? title, IconData? icon, VoidCallback? onTap, Span? from}) {
  final r = inPeriod(store.resultsOf(member.id, t.key), from);
  bool outside(double v) {
    final l = labStatus(t, v, member.sex).level;
    return l != Level.normal && l != Level.none;
  }

  return TrendCard(
    title: title ?? t.name,
    icon: icon,
    unit: t.unit,
    status: labStatus(t, r.last.value, member.sex),
    low: t.lowFor(member.sex),
    high: t.highFor(member.sex),
    points: [for (final x in r) TrendPoint(date: x.date, value: x.value, label: fmtVal(t, x.value), outside: outside(x.value), docId: x.docId)],
    onTap: onTap ?? () => pushPage(context, TestTrendScreen(memberId: member.id, testKey: t.key)),
  );
}

/// Cards stacked in one column on a phone; side by side when there is room (tablets).
class CardColumn extends StatelessWidget {
  const CardColumn({super.key, required this.children, this.cardWidth = 380, this.gap = 10});
  final List<Widget> children;
  final double cardWidth, gap;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = max(1, (box.maxWidth / cardWidth).floor());
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: Wrap(spacing: gap, runSpacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]),
      );
    });
  }
}

/// Every other test with confirmed results (the ones not already shown as a condition).
class _AllTests extends StatelessWidget {
  const _AllTests({required this.store, required this.member, required this.skip, this.from = const Span()});
  final AppStore store;
  final Member member;
  final Set<String> skip;
  final Span from;
  @override
  Widget build(BuildContext context) {
    final mine = store.labs.where((l) => l.memberId == member.id && l.confirmed && !skip.contains(l.testKey));
    List<TestDef> tests(Iterable<LabResult> l) => byUserOrder({for (final x in l) x.testKey}.map(testByKey).whereType<TestDef>(), (t) => 'test:${t.key}', (t) => t.name, store.prefs.healthOrder);
    final shown = tests(mine.where((l) => from.has(l.date)));
    final hidden = tests(mine).length - shown.length;
    if (shown.isEmpty && hidden == 0) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(skip.isEmpty ? 'All tests' : 'Other tests', action: 'Arrange', onAction: () => pushPage(context, ArrangeCardsScreen(memberId: member.id))),
      if (hidden > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Text('$hidden ${hidden == 1 ? 'test has' : 'tests have'} no results in this period', style: TextStyle(fontSize: 13, color: context.c.textSecondary)),
        ),
      const SizedBox(height: 8),
      CardColumn(children: [for (final t in shown) labTrendCard(context, store, member, t, from: from)]),
    ]);
  }
}
