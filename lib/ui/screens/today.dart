import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/features.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
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

void pushPage(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

void openReadingTrend(BuildContext context, String memberId, VitalType type, {bool afterMeal = false}) => pushPage(context, switch (type) {
  VitalType.bp => BpDetailScreen(memberId: memberId),
  VitalType.sugar => TestTrendScreen(memberId: memberId, testKey: afterMeal ? 'ppbs' : 'fbs'),
  _ => ReadingHistoryScreen(memberId: memberId, type: type),
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
  Dose? _justTaken;
  DateTime? _takenAt;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final updates = context.watch<AppUpdateService?>();
    final c = context.c;
    final visible = s.visibleMembers;
    final sel = visible.any((m) => m.id == s.selectedId) ? s.selectedId : null;
    final people = sel == null ? visible : [s.member(sel)!];
    final single = visible.length == 1;
    final now = DateTime.now();

    final all = [for (final m in people) ...s.dosesOn(now, memberId: m.id, now: now)]..sort((a, b) => a.time.compareTo(b.time));
    final due = all.where((d) => d.status == DoseStatus.due).toList();
    final upcoming = all.where((d) => d.status == DoseStatus.upcoming).toList();
    final taken = all.where((d) => d.status == DoseStatus.taken).length;
    final showDose = due.isNotEmpty ? due.first : (upcoming.isNotEmpty ? upcoming.first : null);
    final missed = [for (final m in people) ...s.missedToday(m.id)];
    final appts = [for (final a in s.upcomingAppts()) if (people.any((m) => m.id == a.memberId)) a];
    final review = s.reviewDocs().where((d) => people.any((m) => m.id == d.memberId)).length;

    final week = now.subtract(const Duration(days: 7));
    final readings = s.vitals.where((v) => people.any((m) => m.id == v.memberId) && v.at.isAfter(week)).length;
    final docs = [for (final d in s.docsFor(null)) if (people.any((m) => m.id == d.memberId)) d];
    final who = sel != null ? s.member(sel)!.name : (single ? visible.first.name : s.currentUser.name);

    return Column(children: [
      ScreenHeader(
        title: tr('Today'),
        subtitle: '${fmtWeekday(now)}, ${fmtDay(now)}',
        big: true,
        trailing: headerActions(single ? null : MemberPicker(members: visible, selectedId: sel, includeAll: true, onSelect: s.selectMember)),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kSide, 4, kSide, 32),
          children: staggered([
            _HeroCard(name: who, reports: docs.length, readings: readings, review: review),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _QuickAction(icon: Icons.upload_file_rounded, label: 'Upload report', onTap: () => pushPage(context, const UploadScreen()))),
              const SizedBox(width: 12),
              Expanded(child: _QuickAction(icon: Icons.monitor_heart_rounded, label: 'Log reading', onTap: () => pushPage(context, LogReadingScreen(memberId: sel)))),
            ]),
            const SizedBox(height: 14),
            if (updates != null && (updates.available != null || updates.stage == UpdateStage.downloading)) ...[
              UpdateBanner(u: updates),
              const SizedBox(height: 12),
            ],
            if (review > 0) ...[
              BannerCard(
                icon: Icons.description_rounded,
                tone: 'warn',
                text: review == 1 ? '1 report needs review' : '$review reports need review',
                onTap: () => pushPage(context, const ReviewListScreen()),
              ),
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
            SectionTitle('Latest readings', action: '+ Log', onAction: () => pushPage(context, LogReadingScreen(memberId: sel))),
            Align(alignment: Alignment.centerLeft, child: TextLink('Reading history', icon: Icons.history_rounded, onTap: () => pushPage(context, ReadingHistoryScreen(memberId: sel)))),
            const SizedBox(height: 8),
            if (sel == null && !single)
              _ReadingsAll(people: people)
            else
              SizedBox(
                height: 204,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  children: [
                    for (final w in readingCards(context, s, people.first,
                        onBp: () => openReadingTrend(context, people.first.id, VitalType.bp),
                        onSugar: (after) => openReadingTrend(context, people.first.id, VitalType.sugar, afterMeal: after),
                        onWeight: () => openReadingTrend(context, people.first.id, VitalType.weight)))
                      Padding(padding: const EdgeInsets.only(right: 12, bottom: 12), child: w),
                  ],
                ),
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
    ]);
  }
}

/// Greeting card at the top of Today: who, and a glance at their records.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.name, required this.reports, required this.readings, required this.review});
  final String name;
  final int reports, readings, review;
  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    Widget stat(int n, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: n.toDouble()),
              duration: Duration(milliseconds: reduceMotion(context) ? 0 : 900),
              curve: kEaseOut,
              builder: (_, v, _) => Text('${v.round()}', style: const TextStyle(fontSize: 26, height: 30 / 26, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: .82), fontWeight: FontWeight.w500)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      clipBehavior: Clip.antiAlias,
      // Always the deep teal → indigo, so white text keeps its contrast in dark mode too.
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppPalette.light.accent, AppPalette.light.accent2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(kRadiusCard + 4),
        boxShadow: [BoxShadow(color: AppPalette.light.accent2.withValues(alpha: .22), blurRadius: 22, spreadRadius: -8, offset: const Offset(0, 10))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(right: -18, top: -26, child: Icon(Icons.favorite_rounded, size: 120, color: Colors.white.withValues(alpha: .09))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greet, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(name, style: const TextStyle(fontSize: 24, height: 30 / 24, letterSpacing: -.5, fontWeight: FontWeight.w800, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          Row(children: [stat(reports, 'Reports'), stat(readings, 'Readings · 7d'), stat(review, 'To review')]),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          IconBadge(icon, size: 40),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 2)),
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

class _ReadingsAll extends StatelessWidget {
  const _ReadingsAll({required this.people});
  final List<Member> people;
  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final rows = <Widget>[];
    Widget line(String value, Vital v) => InkWell(
      onTap: () => openReadingTrend(context, v.memberId, v.type, afterMeal: v.afterMeal),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
            StatusPill.info(VitalRanges.ofVital(v)),
            Text(ago(v.at), style: TextStyle(fontSize: 14, color: c.textSecondary)),
          ]),
        )),
      );
    for (final m in people) {
      final bp = s.latestVital(m.id, VitalType.bp);
      final sg = s.latestVital(m.id, VitalType.sugar, afterMeal: false);
      final post = s.latestVital(m.id, VitalType.sugar, afterMeal: true);
      final weight = s.latestVital(m.id, VitalType.weight);
      final oxygen = s.latestVital(m.id, VitalType.spo2);
      if (bp == null && sg == null && post == null && weight == null && oxygen == null) continue;
      rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            MemberAvatar(m, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                // One line per reading, each with its own time — BP and sugar
                // are often logged on different days.
                if (bp != null) line('BP ${bp.a.round()}/${bp.b.round()}', bp),
                if (sg != null) line('Fasting glucose ${sg.a.round()}', sg),
                if (post != null) line('Post-meal glucose ${post.a.round()}', post),
                if (weight != null) line('Weight ${weight.a.toStringAsFixed(2)} kg', weight),
                if (oxygen != null) line('SpO2 ${oxygen.a.round()}%', oxygen),
              ]),
            ),
          ]),
      ));
      rows.add(const Divider1());
    }
    if (rows.isEmpty) {
      return SurfaceCard(child: Text('No readings yet. Tap “+ Log” to add one.', style: TextStyle(fontSize: 15, color: c.textSecondary)));
    }
    rows.removeLast();
    return SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: rows));
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
