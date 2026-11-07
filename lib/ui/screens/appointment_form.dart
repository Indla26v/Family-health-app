import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';

class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key, this.appointment});
  final Appointment? appointment;
  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  late final title = TextEditingController(text: widget.appointment?.title ?? '');
  late final place = TextEditingController(text: widget.appointment?.place ?? '');
  late final reason = TextEditingController(text: widget.appointment?.reason ?? '');
  late final notes = TextEditingController(text: widget.appointment?.notes ?? '');
  late DateTime at = widget.appointment?.at ?? DateTime.now().add(const Duration(days: 7)).copyWith(hour: 10, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  String? memberId, takeDocId, rxDocId;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    takeDocId = widget.appointment?.takeDocId;
    rxDocId = widget.appointment?.prescriptionDocId;
  }

  @override
  void dispose() {
    for (final t in [title, place, reason, notes]) {
      t.dispose();
    }
    super.dispose();
  }

  void _save() {
    setState(() => _tried = true);
    if (title.text.trim().isEmpty) return;
    final s = readStore(context);
    final a = widget.appointment;
    if (a != null) {
      a
        ..title = title.text.trim()
        ..place = place.text.trim()
        ..reason = reason.text.trim()
        ..notes = notes.text.trim()
        ..at = at
        ..takeDocId = takeDocId
        ..prescriptionDocId = rxDocId;
      s.saveAppointment(a);
    } else {
      s.saveAppointment(Appointment(id: s.newId('ap'), memberId: memberId!, title: title.text.trim(), place: place.text.trim(), at: at, reason: reason.text.trim(), notes: notes.text.trim(), takeDocId: takeDocId, prescriptionDocId: rxDocId), isNew: true);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??= widget.appointment?.memberId ?? (people.any((m) => m.id == s.selectedId) ? s.selectedId : people.first.id);
    final isEdit = widget.appointment != null;
    final past = at.isBefore(DateTime.now());
    final docs = s.docsFor(memberId);

    Widget field(String label, TextEditingController ctl, {String? hint, int lines = 1, bool err = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 6),
          TextField(controller: ctl, maxLines: lines, minLines: lines, textCapitalization: TextCapitalization.sentences, style: const TextStyle(fontSize: 16), decoration: InputDecoration(hintText: hint, errorText: err ? 'Required' : null)),
        ]);

    Widget docPicker(String label, String? value, ValueChanged<String?> on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: docs.any((d) => d.id == value) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(),
            style: TextStyle(fontSize: 15, color: c.text),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('None')), for (final d in docs) DropdownMenuItem<String?>(value: d.id, child: Text('${d.lab} · ${fmtDate(d.date)}', overflow: TextOverflow.ellipsis))],
            onChanged: on,
          ),
        ]);

    return PageBody(
      header: ScreenHeader(title: isEdit ? 'Edit appointment' : 'Add appointment', back: true),
      spacing: 18,
      bottom: BigButton(label: 'Save appointment', onTap: _save),
      children: [
        if (!isEdit && people.length > 1) MemberSwitcher(members: people, selectedId: memberId, onSelect: (id) => setState(() => memberId = id)),
        field('Doctor or visit', title, hint: 'e.g. Endocrinologist', err: _tried && title.text.trim().isEmpty),
        field('Hospital or clinic', place, hint: 'e.g. City Hospital'),
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: at, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 730)));
                if (d != null) setState(() => at = DateTime(d.year, d.month, d.day, at.hour, at.minute));
              },
              child: Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)), child: Row(children: [Icon(Icons.calendar_month_rounded, color: c.textSecondary), const SizedBox(width: 8), Flexible(child: Text(fmtDate(at), style: const TextStyle(fontSize: 15)))])),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(at));
                if (t != null) setState(() => at = DateTime(at.year, at.month, at.day, t.hour, t.minute));
              },
              child: Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)), child: Row(children: [Icon(Icons.schedule_rounded, color: c.textSecondary), const SizedBox(width: 8), Text(fmtTime(at), style: const TextStyle(fontSize: 15))])),
            ),
          ),
        ]),
        field('Reason', reason, hint: 'e.g. HbA1c review'),
        if (!past) docPicker('Report to take along', takeDocId, (v) => setState(() => takeDocId = v)),
        if (past) ...[
          field('Doctor’s notes', notes, hint: 'What the doctor said, in their words', lines: 3),
          docPicker('Prescription', rxDocId, (v) => setState(() => rxDocId = v)),
        ],
        if (isEdit)
          BigButton(
            label: 'Delete appointment',
            secondary: true,
            icon: Icons.delete_outline_rounded,
            onTap: () async {
              final s2 = readStore(context);
              if (await confirmDialog(context, 'Delete this appointment?', 'It will be removed from this phone.')) {
                s2.deleteAppointment(widget.appointment!.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
      ],
    );
  }
}
