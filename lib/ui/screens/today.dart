import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/features.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/reading_metric.dart';
import '../../services/app_update.dart';
import '../widgets/common.dart';
import '../widgets/metric_card.dart';
import '../widgets/motion.dart';
import '../widgets/readings.dart';
import '../widgets/update_ui.dart';
import 'adherence.dart';
import 'appointment_form.dart';
import 'appointments.dart';
import 'bp_detail.dart';
import 'log_reading.dart';
import 'medicines.dart';
import 'records.dart';
import 'reading_history.dart';
import 'test_trend.dart';
import 'review.dart';
import 'upload.dart';
import 'weight_trend.dart';

void pushPage(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

void openReadingTrend(BuildContext context, String memberId, VitalType type, {bool afterMeal = false}) => pushPage(context, switch (type) {
  VitalType.bp => BpDetailScreen(memberId: memberId),
  VitalType.sugar => TestTrendScreen(memberId: memberId, testKey: afterMeal ? 'ppbs' : 'fbs'),
  VitalType.weight => WeightTrendScreen(memberId: memberId),
  VitalType.spo2 => VitalTrendScreen(memberId: memberId, metric: ReadingMetric.oxygen),
});

String foodText(Food f) => switch (f) { Food.before => 'Before food', Food.after => 'After food', Food.any => '' };

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.onSeeRecords});

  /// Switches to the Records tab ("See all" on Latest reports).
  final VoidCallback? onSeeRecords;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _readingsKey = GlobalKey<LatestReadingsSectionState>();
  Dose? _justTaken;
  DateTime? _takenAt;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final updates = context.watch<AppUpdateService?>();
    final updating = updates?.stage == UpdateStage.downloading || updates?.stage == UpdateStage.openingInstaller;
    final dockInset = MediaQuery.paddingOf(context).bottom;
    final c = context.c;
    final visible = s.visibleMembers;
    final sel = visible.any((m) => m.id == s.selectedId) ? s.selectedId : null;
    final people = sel == null ? visible : [s.member(sel)!];
    final single = visible.length == 1;
    final now = DateTime.now();

    final all = [if (kMedicinesEnabled) for (final m in people) ...s.dosesOn(now, memberId: m.id, now: now)]..sort((a, b) => a.time.compareTo(b.time));
    final due = all.where((d) => d.status == DoseStatus.due).toList();
    final upcoming = all.where((d) => d.status == DoseStatus.upcoming).toList();
    final taken = all.where((d) => d.status == DoseStatus.taken).length;
    final showDose = due.isNotEmpty ? due.first : (upcoming.isNotEmpty ? upcoming.first : null);
    final missed = [if (kMedicinesEnabled) for (final m in people) ...s.missedToday(m.id)];
    final appts = [if (kAppointmentsEnabled) for (final a in s.upcomingAppts()) if (people.any((m) => m.id == a.memberId)) a];
    final ids = people.map((member) => member.id).toSet();
    final docs = s.docsFor(null).where((doc) => ids.contains(doc.memberId)).toList();
    final review = docs.where((doc) => doc.status == DocStatus.needsReview).length;
    final weekAgo = now.subtract(const Duration(days: 7));
    final readings = s.vitals.where((reading) =>
        ids.contains(reading.memberId) && !reading.at.isBefore(weekAgo) && !reading.at.isAfter(now)).length;
    final who = sel != null ? s.member(sel)!.name : (single ? visible.first.name : 'Family');

    return Stack(children: [
      Column(children: [
      ScreenHeader(
        title: tr('Today'),
        subtitle: '${fmtWeekday(now)}, ${fmtDay(now)}',
        big: true,
        trailing: headerActions(single ? null : MemberPicker(members: visible, selectedId: sel, includeAll: true, onSelect: s.selectMember)),
      ),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _readingsKey.currentState?.handleScroll(notification);
            return false;
          },
          child: ListView(
          padding: EdgeInsets.fromLTRB(kSide, 4, kSide, updating ? 200 : 108),
          children: staggered([
            _TodaySummary(
              name: who,
              hour: now.hour,
              reports: docs.length,
              readings: readings,
              review: review,
              onReview: review == 0 ? null : () => pushPage(context, ReviewListScreen(memberId: sel)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _QuickAction(
                icon: Icons.upload_file_rounded,
                label: 'Upload report',
                onTap: () => pushPage(context, UploadScreen(memberId: sel)),
              )),
              const SizedBox(width: 8),
              Expanded(child: _QuickAction(
                icon: Icons.monitor_heart_rounded,
                label: 'Log reading',
                onTap: () => pushPage(context, LogReadingScreen(memberId: sel)),
              )),
            ]),
            const SizedBox(height: 12),
            if (updates != null && !updating && updates.available != null) ...[
              UpdateBanner(u: updates),
              const SizedBox(height: 12),
            ],
            if (kMedicinesEnabled && missed.isNotEmpty) ...[
              BannerCard(
                icon: Icons.cancel_rounded,
                tone: 'danger',
                text: 'Missed: ${s.member(missed.first.med.memberId)?.name}, ${fmtTime(missed.first.time)} ${missed.first.med.name}${missed.length > 1 ? '  +${missed.length - 1} more' : ''}',
                trailing: TextLink('View', onTap: () => pushPage(context, AdherenceScreen(memberId: missed.first.med.memberId))),
              ),
              const SizedBox(height: 12),
            ],
            // ---- medicine card
            if (kMedicinesEnabled) ...[
              if (_justTaken != null && _takenAt != null)
                _DoneCard(dose: _justTaken!, at: _takenAt!, member: s.member(_justTaken!.med.memberId), showMember: sel == null && !single, onUndo: () {
                  s.undoDose(_justTaken!);
                  setState(() => _justTaken = null);
                }, onDismiss: () => setState(() => _justTaken = null), taken: taken, total: all.length)
              else if (showDose != null)
                _DoseCard(
                  dose: showDose,
                  member: s.member(showDose.med.memberId),
                  showMember: sel == null && !single,
                  taken: taken,
                  total: all.length,
                  more: (due.isEmpty ? upcoming.length : due.length) - 1,
                  onTaken: () {
                    s.takeDose(showDose);
                    setState(() {
                      _justTaken = showDose;
                      _takenAt = DateTime.now();
                    });
                  },
                  onSkip: () => s.skipDose(showDose),
                  onAll: () => pushPage(context, MedicinesScreen(memberId: showDose.med.memberId)),
                )
              else
                SurfaceCard(
                  child: Row(children: [
                    IconBadge(all.isEmpty ? Icons.medication_rounded : Icons.check_circle_rounded, size: 48),
                    const SizedBox(width: 14),
                    Expanded(child: Text(all.isEmpty ? tr('No medicines due') : tr('All doses done for today'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    if (all.isNotEmpty) ProgressRing(fraction: all.isEmpty ? 0 : taken / all.length, label: '$taken/${all.length}', size: 60),
                  ]),
                ),
              const SizedBox(height: 20),
            ],
            // ---- readings
            LatestReadingsSection(
              key: _readingsKey,
              people: people,
              store: s,
              onTrend: (m, metric) => openReadingTrend(context, m.id, metric.type, afterMeal: metric.afterMeal ?? false),
              onAdd: (m) => pushPage(context, LogReadingScreen(memberId: m.id)),
              onHistory: (m) => pushPage(context, ReadingHistoryScreen(memberId: m.id)),
            ),
            if (kAppointmentsEnabled) ...[
              const SizedBox(height: 12),
              const SectionTitle('Next appointment'),
              const SizedBox(height: 8),
              if (appts.isEmpty)
                SurfaceCard(
                  onTap: () => pushPage(context, const AppointmentsScreen()),
                  child: Row(children: [
                    IconBadge(Icons.calendar_month_rounded, color: c.textSecondary, tint: c.surfaceAlt),
                    const SizedBox(width: 14),
                    const Expanded(child: Text('No appointments yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    TextLink('Add', onTap: () => pushPage(context, const AppointmentFormScreen())),
                  ]),
                )
              else
                _ApptCard(a: appts.first, showMember: sel == null && !single),
            ],
            // ---- latest reports
            const SizedBox(height: 12),
            SectionTitle('Latest reports', action: docs.isEmpty || widget.onSeeRecords == null ? null : 'See all', onAction: widget.onSeeRecords),
            const SizedBox(height: 8),
            if (docs.isEmpty)
              SurfaceCard(
                onTap: () => pushPage(context, const UploadScreen()),
                child: Row(children: [
                  const IconBadge(Icons.description_rounded, size: 44),
                  const SizedBox(width: 14),
                  Expanded(child: Text('No reports yet. Upload one to see trends.', style: TextStyle(fontSize: 15, color: c.textSecondary))),
                ]),
              )
            else
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(children: [
                  for (var i = 0; i < docs.length && i < 3; i++) ...[if (i > 0) const Divider1(), DocRow(doc: docs[i], showMember: sel == null && !single)],
                ]),
              ),
          ]),
          ),
        ),
      ),
      ]),
      Positioned(
        left: kSide, right: kSide, bottom: dockInset + 8,
        child: AnimatedSwitcher(
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220),
          child: updating && updates != null
              ? Center(child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: UpdateProgressCard(u: updates),
                ))
              : const SizedBox.shrink(),
        ),
      ),
    ]);
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.name, required this.hour, required this.reports,
    required this.readings, required this.review, this.onReview});
  final String name;
  final int hour, reports, readings, review;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    Widget stat(int count, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$count', style: const TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
        Text(tr(label), style: const TextStyle(fontSize: 13, color: Colors.white)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppPalette.light.gradient,
        borderRadius: BorderRadius.circular(kRadiusCard + 4),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        const Positioned(top: -25, right: -15,
          child: ExcludeSemantics(child: Icon(Icons.favorite_rounded, size: 120, color: Color(0x1AFFFFFF)))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(greeting), style: const TextStyle(fontSize: 15, color: Colors.white)),
          Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: stat(reports, 'Reports')),
            const SizedBox(width: 8),
            Expanded(child: stat(readings, 'Readings · 7d')),
            const SizedBox(width: 8),
            Expanded(child: Semantics(
              button: onReview != null,
              child: InkWell(
                onTap: onReview,
                borderRadius: BorderRadius.circular(8),
                child: stat(review, 'To review'),
              ),
            )),
          ]),
        ]),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    child: Row(children: [
      IconBadge(icon, size: 36),
      const SizedBox(width: 8),
      Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
    ]),
  );
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose, required this.member, required this.showMember, required this.taken, required this.total, required this.more, required this.onTaken, required this.onSkip, required this.onAll});
  final Dose dose;
  final Member? member;
  final bool showMember;
  final int taken, total, more;
  final VoidCallback onTaken, onSkip, onAll;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDue = dose.status == DoseStatus.due;
    final food = foodText(dose.med.food);
    return SurfaceCard(
      gradient: c.softGradient,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (showMember && member != null) ...[MemberAvatar(member, size: 32), const SizedBox(width: 8)],
          Expanded(
            child: Text('${isDue ? tr('Due now') : 'Next'} • ${fmtTime(dose.time)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isDue ? c.accent : c.textSecondary)),
          ),
          TextLink('All medicines', onTap: onAll),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconBadge(Icons.medication_rounded, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dose.med.label, style: AppText.title),
              Text('${_tablets(dose.med.tablets)}${food.isEmpty ? '' : ' • ${tr(food)}'}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
            ]),
          ),
          ProgressRing(fraction: total == 0 ? 0 : taken / total, label: '$taken/$total'),
        ]),
        if (more > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('+$more more ${isDue ? 'due now' : 'later today'}', style: TextStyle(fontSize: 14, color: c.textSecondary))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(flex: 3, child: BigButton(label: tr('Taken'), icon: Icons.check_rounded, onTap: onTaken)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: BigButton(label: tr('Skip'), secondary: true, onTap: onSkip)),
        ]),
      ]),
    );
  }
}

String _tablets(double t) => t == 1 ? '1 tablet' : '${t == t.roundToDouble() ? t.toInt() : t} tablets';

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.dose, required this.at, required this.member, required this.showMember, required this.onUndo, required this.onDismiss, required this.taken, required this.total});
  final Dose dose;
  final DateTime at;
  final Member? member;
  final bool showMember;
  final VoidCallback onUndo, onDismiss;
  final int taken, total;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SurfaceCard(
      color: c.tint(c.ok, .10),
      child: Row(children: [
        Icon(Icons.check_circle_rounded, size: 40, color: c.ok),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dose.med.label}${showMember && member != null ? ' · ${member!.name}' : ''}', style: AppText.title),
            Text('Taken at ${fmtTime(at)}', style: TextStyle(fontSize: 15, color: c.ok, fontWeight: FontWeight.w600)),
          ]),
        ),
        TextLink(tr('Undo'), onTap: onUndo),
        IconButton(onPressed: onDismiss, tooltip: 'Dismiss', icon: const Icon(Icons.close_rounded)),
      ]),
    );
  }
}

class _ApptCard extends StatelessWidget {
  const _ApptCard({required this.a, required this.showMember});
  final Appointment a;
  final bool showMember;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = watchStore(context);
    final m = s.member(a.memberId);
    return SurfaceCard(
      color: c.tint(c.accent2, .08),
      onTap: () => pushPage(context, const AppointmentsScreen()),
      child: Row(children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(fmtWeekday(a.at).toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accent)),
            Text('${a.at.day}', style: const TextStyle(fontSize: 23, height: 30 / 26, fontWeight: FontWeight.w700)),
            Text(['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][a.at.month - 1], style: TextStyle(fontSize: 14, color: c.textSecondary)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: AppText.title),
            Text('${a.place.isEmpty ? 'Place to add' : a.place} · ${fmtTime(a.at)}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
            if (a.reason.isNotEmpty || showMember) Text([if (a.reason.isNotEmpty) a.reason, if (showMember && m != null) m.name].join(' · '), style: TextStyle(fontSize: 14, color: c.textSecondary)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      ]),
    );
  }
}
