import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'adherence.dart';
import 'medicine_form.dart';
import 'today.dart';

/// Small pill photo (or generic pill icon) used on medicine rows.
class PillThumb extends StatelessWidget {
  const PillThumb(this.med, {super.key, this.size = 40, this.color});
  final Medicine med;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = color ?? c.accent;
    final path = med.photoPath;
    final hasPhoto = !kIsWeb && path != null && File(path).existsSync();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: col.withValues(alpha: .14), borderRadius: BorderRadius.circular(size * .32)),
      child: hasPhoto ? Image.file(File(path), fit: BoxFit.cover) : Icon(Icons.medication_rounded, size: size * .56, color: col),
    );
  }
}

class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({super.key, this.memberId});
  final String? memberId;
  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  String? memberId;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??= people.any((m) => m.id == widget.memberId) ? widget.memberId : people.first.id;
    final m = s.member(memberId)!;
    final now = DateTime.now();
    final doses = s.dosesOn(now, memberId: m.id, now: now);
    final month = s.adherenceMonth(m.id, DateTime(now.year, now.month));
    final exp = month.values.fold<int>(0, (a, e) => a + e.$1), got = month.values.fold<int>(0, (a, e) => a + e.$2);
    final pct = exp == 0 ? null : (got * 100 / exp).round();

    String slotOf(int h) => h < 12 ? 'Morning' : (h < 17 ? 'Afternoon' : 'Night');
    final groups = {
      'Morning': <Dose>[],
      'Afternoon': <Dose>[],
      'Night': <Dose>[],
    };
    for (final d in doses) {
      groups[slotOf(d.slot.hour)]!.add(d);
    }
    final icons = {'Morning': Icons.wb_sunny_rounded, 'Afternoon': Icons.wb_twilight_rounded, 'Night': Icons.nightlight_round};

    return PageBody(
      header: ScreenHeader(title: tr('Medicines'), back: true, trailing: headerActions(MemberPicker(members: people, selectedId: memberId, onSelect: (id) => setState(() => memberId = id)))),
      bottom: BigButton(label: tr('Add medicine'), icon: Icons.add_rounded, onTap: () => pushPage(context, MedicineFormScreen(memberId: m.id))),
      children: [
        SurfaceCard(
          onTap: () => pushPage(context, AdherenceScreen(memberId: m.id)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('This month', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                Text(pct == null ? '–' : '$pct%', style: AppText.displayNumber),
                Text('doses taken', style: TextStyle(fontSize: 15, color: c.textSecondary)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          ]),
        ),
        if (s.medsOf(m.id).isEmpty)
          const EmptyState(icon: Icons.medication_rounded, message: 'No medicines yet', detail: 'Add one to get reminders.'),
        for (final g in groups.entries)
          if (s.medsOf(m.id).isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Row(children: [Icon(icons[g.key], size: 22, color: c.accent), const SizedBox(width: 8), Text(tr(g.key), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))]),
              ),
              if (g.value.isEmpty)
                SizedBox(width: double.infinity, child: SurfaceCard(child: Text(tr('No medicines'), style: TextStyle(fontSize: 15, color: c.textSecondary))))
              else
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    for (var i = 0; i < g.value.length; i++) ...[
                      if (i > 0) const Divider1(),
                      _DoseRow(dose: g.value[i], member: m),
                    ],
                  ]),
                ),
            ]),
      ],
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose, required this.member});
  final Dose dose;
  final Member member;
  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = dose.med;
    final food = foodText(m.food);
    final low = s.needsRefill(m);
    final days = s.daysLeft(m).floor();
    final refillBy = DateTime.now().add(Duration(days: (s.daysLeft(m) - 1).floor().clamp(0, 999)));

    Widget trailing;
    switch (dose.status) {
      case DoseStatus.taken:
        trailing = StatusPill(label: 'Taken', tone: 'ok');
      case DoseStatus.missed:
        trailing = StatusPill(label: 'Missed', tone: 'danger');
      case DoseStatus.skipped:
        trailing = StatusPill(label: 'Skipped', tone: 'muted', icon: Icons.skip_next_rounded);
      case DoseStatus.due:
        trailing = SizedBox(
          width: 112,
          child: BigButton(label: tr('Taken'), icon: Icons.check_rounded, height: 48, onTap: () => s.takeDose(dose)),
        );
      case DoseStatus.upcoming:
        trailing = StatusPill(label: 'Later', tone: 'muted');
    }

    return InkWell(
      onTap: () => pushPage(context, MedicineFormScreen(medicine: m)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          PillThumb(m, color: member.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text('${fmtTime(dose.time)}${food.isEmpty ? '' : ' · ${tr(food)}'}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              if (low)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Icons.error_rounded, size: 16, color: c.warn),
                    const SizedBox(width: 4),
                    Flexible(child: Text('$days days left · refill by ${fmtDay(refillBy)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.warn))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      ),
    );
  }
}
