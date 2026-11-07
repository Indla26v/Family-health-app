import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'appointment_form.dart';
import 'doc_viewer.dart';
import 'today.dart';

class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final up = s.upcomingAppts();
    final past = s.pastAppts();
    return PageBody(
      header: ScreenHeader(title: tr('Appointments'), back: true, trailing: const SettingsButton()),
      children: [
        Row(children: [
          Expanded(child: Text(tr('Upcoming appointments'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          TextLink('+ Add', onTap: () => pushPage(context, const AppointmentFormScreen())),
        ]),
        if (up.isEmpty)
          EmptyState(icon: Icons.calendar_month_rounded, message: 'No appointments coming up', buttonLabel: 'Add appointment', onButton: () => pushPage(context, const AppointmentFormScreen()))
        else
          for (final a in up) _ApptTile(a: a),
        if (past.isNotEmpty) ...[
          Text(tr('Past visits'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          for (final a in past) _ApptTile(a: a, past: true),
        ],
        Text('Notes are for your records. Not medical advice.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
      ],
    );
  }
}

class _ApptTile extends StatelessWidget {
  const _ApptTile({required this.a, this.past = false});
  final Appointment a;
  final bool past;
  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = s.member(a.memberId);
    final take = s.doc(a.takeDocId);
    final rx = s.doc(a.prescriptionDocId);
    const mo = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    Widget docLink(IconData icon, String text, String id) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openDocument(context, id),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [Icon(icon, size: 20, color: c.accent), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.accent))), Icon(Icons.chevron_right_rounded, color: c.accent)]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: SurfaceCard(
        onTap: () => pushPage(context, AppointmentFormScreen(appointment: a)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: past ? c.surfaceAlt : c.accentTint, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text(fmtWeekday(a.at).toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: past ? c.textSecondary : c.accent)),
                Text('${a.at.day}', style: const TextStyle(fontSize: 21, height: 28 / 24, fontWeight: FontWeight.w700)),
                Text(mo[a.at.month - 1], style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: AppText.title),
                const SizedBox(height: 2),
                Row(children: [Icon(Icons.location_on_rounded, size: 16, color: c.textSecondary), const SizedBox(width: 4), Flexible(child: Text(a.place.isEmpty ? 'Add the place' : a.place, style: TextStyle(fontSize: 14, color: a.place.isEmpty ? c.textSecondary.withValues(alpha: .7) : c.textSecondary)))]),
                Row(children: [Icon(Icons.schedule_rounded, size: 16, color: c.textSecondary), const SizedBox(width: 4), Text(fmtTime(a.at), style: TextStyle(fontSize: 14, color: c.textSecondary))]),
                const SizedBox(height: 6),
                Row(children: [
                  if (m != null) MemberAvatar(m, size: 26),
                  const SizedBox(width: 8),
                  if (a.reason.isNotEmpty) Flexible(child: Text(a.reason, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                ]),
              ]),
            ),
          ]),
          if (past && a.notes.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text.rich(TextSpan(children: [const TextSpan(text: 'Doctor’s notes: ', style: TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: a.notes)]), style: const TextStyle(fontSize: 14, height: 21 / 15))),
          if (past && a.notes.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Doctor’s notes: tap to add', style: TextStyle(fontSize: 14, color: c.textSecondary))),
          if (!past && take != null) docLink(Icons.description_rounded, 'Take: ${take.lab} · ${fmtDate(take.date)}', take.id),
          if (past && rx != null) docLink(Icons.description_rounded, '${rx.lab} · ${fmtDate(rx.date)}', rx.id),
        ]),
      ),
    );
  }
}
