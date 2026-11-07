import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/reminders.dart';
import '../widgets/common.dart';

void openReminderFromPayload(AppStore store, String payload) {
  final p = payload.split(':');
  if (p.length != 4 || p[0] != 'dose') return;
  final med = store.medicine(p[1]);
  if (med == null) return;
  final now = DateTime.now();
  final h = int.tryParse(p[2]), m = int.tryParse(p[3]);
  if (h == null || m == null) return;
  final dose = store.dosesOn(now, memberId: med.memberId, now: now).where((d) => d.med.id == med.id && d.slot.hour == h && d.slot.minute == m).firstOrNull;
  if (dose == null) return;
  navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => ReminderScreen(dose: dose), fullscreenDialog: true));
}

String teluguInstruction(Medicine m) {
  final food = switch (m.food) { Food.before => 'భోజనానికి ముందు ', Food.after => 'భోజనం తర్వాత ', Food.any => '' };
  final n = m.tablets == m.tablets.roundToDouble() ? m.tablets.toInt().toString() : m.tablets.toString();
  return '$food$n మాత్ర వేసుకోండి';
}

/// Full-screen alarm: huge pill, two giant buttons, and a small Skip link.
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key, required this.dose});
  final Dose dose;
  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  String? done; // taken | snooze | skip

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    final s = readStore(context);
    if (s.prefs.voice) {
      final m = widget.dose.med;
      Voice.speak('${m.teluguName.isEmpty ? m.name : m.teluguName}. ${teluguInstruction(m)}', 'Time for ${m.label}. ${_en(m)}');
    }
  }

  @override
  void dispose() {
    Voice.stop();
    super.dispose();
  }

  String _en(Medicine m) => '${m.tablets == 1 ? '1 tablet' : '${m.tablets} tablets'}${m.food == Food.any ? '' : ' · ${m.food == Food.after ? 'After food' : 'Before food'}'}';

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final d = widget.dose;
    final m = d.med;
    final who = s.member(m.memberId);
    final photo = (!kIsWeb && m.photoPath != null && File(m.photoPath!).existsSync()) ? m.photoPath : null;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(children: [
            Row(children: [
              Icon(Icons.notifications_active_rounded, color: c.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Medicine time'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.accent))),
              Flexible(child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  s.setPref((p) => p.voice = !p.voice);
                  if (!s.prefs.voice) Voice.stop();
                },
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(s.prefs.voice ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 20, color: c.textSecondary), const SizedBox(width: 6), Flexible(child: Text(tr(s.prefs.voice ? 'Voice on' : 'Voice off'), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.textSecondary)))]),
                ),
              )),
            ]),
            const Spacer(),
            Text(fmtTime(d.time), style: const TextStyle(fontSize: 46, height: 1.1, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 8),
            if (who != null)
              Row(mainAxisSize: MainAxisSize.min, children: [MemberAvatar(who, size: 36), const SizedBox(width: 8), Text(who.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))]),
            const SizedBox(height: 24),
            Container(
              width: 160,
              height: 160,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: (who?.color ?? c.accent).withValues(alpha: .14), borderRadius: BorderRadius.circular(56)),
              child: photo != null ? Image.file(File(photo), fit: BoxFit.cover) : Icon(Icons.medication_rounded, size: 84, color: who?.color ?? c.accent),
            ),
            const SizedBox(height: 20),
            Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, height: 38 / 30, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_en(m), style: TextStyle(fontSize: 18, color: c.textSecondary)),
            const SizedBox(height: 2),
            Text(teluguInstruction(m), textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, height: 32 / 22)),
            const Spacer(),
            if (done == null) ...[
              BigButton(
                label: 'Taken · తీసుకున్నాను',
                icon: Icons.check_rounded,
                height: 88,
                fontSize: 21,
                onTap: () {
                  s.takeDose(d);
                  setState(() => done = 'taken');
                },
              ),
              const SizedBox(height: 12),
              BigButton(
                label: 'Snooze 10 min',
                icon: Icons.schedule_rounded,
                secondary: true,
                height: 72,
                fontSize: 18,
                onTap: () {
                  Reminders.snooze(m, d.slot, 10);
                  setState(() => done = 'snooze');
                },
              ),
              const SizedBox(height: 4),
              TextLink(tr('Skip this dose'), onTap: () {
                s.skipDose(d);
                setState(() => done = 'skip');
              }),
            ] else ...[
              Container(
                height: 88,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: done == 'snooze' ? c.infoTint : c.accentTint, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(done == 'snooze' ? Icons.schedule_rounded : Icons.check_circle_rounded, size: 30, color: done == 'snooze' ? c.info : c.accent),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      switch (done) { 'snooze' => 'Reminding again at ${fmtTime(DateTime.now().add(const Duration(minutes: 10)))}', 'skip' => 'Skipped', _ => 'Taken at ${fmtTime(DateTime.now())}' },
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: done == 'snooze' ? c.info : c.accent),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              BigButton(label: tr('Close'), secondary: true, onTap: () => Navigator.of(context).maybePop()),
            ],
          ]),
        ),
      ),
    );
  }
}
