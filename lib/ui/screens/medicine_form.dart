import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'medicines.dart';

/// Add / edit a medicine: photo, name, strength, food, schedule, stock.
class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({super.key, this.medicine, this.memberId});
  final Medicine? medicine;
  final String? memberId;
  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  late final name = TextEditingController(text: widget.medicine?.name ?? '');
  late final strength = TextEditingController(text: widget.medicine?.strength ?? '');
  late final stock = TextEditingController(text: widget.medicine == null ? '30' : _n(widget.medicine!.stock));
  late final refill = TextEditingController(text: '${widget.medicine?.refillDays ?? 7}');
  late final tablets = TextEditingController(text: widget.medicine == null ? '1' : _n(widget.medicine!.tablets));
  late Food food = widget.medicine?.food ?? Food.after;
  String? memberId;
  String? photo;
  bool _tried = false;

  // slot -> (enabled, hour, minute)
  late final Map<String, (bool, int, int)> slots = () {
    final d = {'Morning': (false, 8, 0), 'Afternoon': (false, 13, 30), 'Night': (false, 20, 0)};
    for (final t in widget.medicine?.times ?? <DoseTime>[]) {
      final k = t.hour < 12 ? 'Morning' : (t.hour < 17 ? 'Afternoon' : 'Night');
      d[k] = (true, t.hour, t.minute);
    }
    if (widget.medicine == null) {
      d['Morning'] = (true, 8, 0);
      d['Night'] = (true, 20, 0);
    }
    return d;
  }();

  static String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    photo = widget.medicine?.photoPath;
  }

  @override
  void dispose() {
    for (final t in [name, strength, stock, refill, tablets]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final f = await ImagePicker().pickImage(source: (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) ? ImageSource.gallery : ImageSource.camera, maxWidth: 800, imageQuality: 80);
      if (f == null) return;
      if (kIsWeb) return;
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/pills');
      await dir.create(recursive: true);
      final dest = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(f.path).copy(dest.path);
      setState(() => photo = dest.path);
    } catch (e) {
      if (mounted) toast(context, 'Could not open the camera');
    }
  }

  Future<void> _pickTime(String k) async {
    final cur = slots[k]!;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur.$2, minute: cur.$3));
    if (t != null) setState(() => slots[k] = (cur.$1, t.hour, t.minute));
  }

  void _save() {
    setState(() => _tried = true);
    final times = [for (final e in slots.entries) if (e.value.$1) DoseTime(e.key == 'Morning' ? 'morning' : (e.key == 'Afternoon' ? 'afternoon' : 'night'), e.value.$2, e.value.$3)];
    if (name.text.trim().isEmpty || times.isEmpty) return;
    final s = readStore(context);
    final med = widget.medicine;
    if (med != null) {
      med
        ..name = name.text.trim()
        ..strength = strength.text.trim()
        ..food = food
        ..times = times
        ..stock = double.tryParse(stock.text) ?? med.stock
        ..refillDays = int.tryParse(refill.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 7
        ..tablets = double.tryParse(tablets.text) ?? 1
        ..photoPath = photo;
      s.saveMedicine(med);
    } else {
      s.saveMedicine(
        Medicine(
          id: s.newId('med'),
          memberId: memberId!,
          name: name.text.trim(),
          strength: strength.text.trim(),
          food: food,
          times: times,
          stock: double.tryParse(stock.text) ?? 30,
          startDate: DateTime.now(),
          refillDays: int.tryParse(refill.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 7,
          tablets: double.tryParse(tablets.text) ?? 1,
          photoPath: photo,
        ),
        isNew: true,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??= widget.medicine?.memberId ?? (people.any((m) => m.id == widget.memberId) ? widget.memberId : (people.any((m) => m.id == s.selectedId) ? s.selectedId : people.first.id));
    final isEdit = widget.medicine != null;
    final who = s.member(memberId);
    final noTimes = slots.values.every((e) => !e.$1);

    Widget field(String label, TextEditingController ctl, {TextInputType? type, String? hint, List<TextInputFormatter>? fmt, bool err = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: ctl,
            keyboardType: type,
            inputFormatters: fmt,
            style: const TextStyle(fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: hint, errorText: err ? 'Required' : null, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18)),
          ),
        ]);

    return PageBody(
      header: ScreenHeader(title: isEdit ? 'Edit medicine' : tr('Add medicine'), subtitle: 'For ${who?.name ?? ''}', back: true),
      spacing: 18,
      bottom: BigButton(label: tr('Save medicine'), onTap: _save),
      children: [
        if (!isEdit && people.length > 1)
          MemberSwitcher(members: people, selectedId: memberId, onSelect: (id) => setState(() => memberId = id)),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _takePhoto,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.accent, width: 1.5)),
            child: Row(children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
                child: (!kIsWeb && photo != null && File(photo!).existsSync()) ? Image.file(File(photo!), fit: BoxFit.cover) : Icon(Icons.photo_camera_rounded, size: 30, color: c.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(photo == null ? 'Take a photo of the strip' : 'Retake photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.accent)),
                  Text('Helps parents recognise the pill', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                ]),
              ),
            ]),
          ),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: field('Medicine name', name, hint: 'e.g. Metformin', err: _tried && name.text.trim().isEmpty)),
          const SizedBox(width: 12),
          Expanded(child: field('Strength', strength, hint: 'e.g. 500 mg')),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('When to take', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 8),
          Row(children: [
            for (final (f, l) in [(Food.before, 'Before food'), (Food.after, 'After food'), (Food.any, 'Any time')])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: f == Food.any ? 0 : 8),
                  child: Semantics(
                    button: true,
                    selected: food == f,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => food = f),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: food == f ? c.accentTint : c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: food == f ? c.accent : c.border, width: 1.5)),
                        child: Text(tr(l), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Schedule · every day', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 8),
          for (final k in ['Morning', 'Afternoon', 'Night'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 64,
                decoration: BoxDecoration(color: slots[k]!.$1 ? c.accentTint : c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: slots[k]!.$1 ? c.accent : c.border, width: 1.5)),
                child: Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => slots[k] = (!slots[k]!.$1, slots[k]!.$2, slots[k]!.$3)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(color: slots[k]!.$1 ? c.accent : c.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: slots[k]!.$1 ? c.accent : c.border, width: 2)),
                            child: slots[k]!.$1 ? Icon(Icons.check_rounded, size: 18, color: c.onAccent) : null,
                          ),
                          const SizedBox(width: 12),
                          Text(tr(k), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: slots[k]!.$1 ? () => _pickTime(k) : null,
                    style: TextButton.styleFrom(minimumSize: const Size(100, 56), foregroundColor: c.textSecondary),
                    child: Text(fmtHm(slots[k]!.$2, slots[k]!.$3), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: slots[k]!.$1 ? c.text : c.textSecondary, decoration: slots[k]!.$1 ? TextDecoration.underline : null)),
                  ),
                ]),
              ),
            ),
          if (_tried && noTimes) Text('Pick at least one time', style: TextStyle(fontSize: 14, color: c.danger, fontWeight: FontWeight.w600)),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: field('Tablets per dose', tablets, type: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 12),
          Expanded(child: field('Tablets in stock', stock, type: const TextInputType.numberWithOptions(decimal: true))),
        ]),
        field('Remind to refill when days left ≤', refill, type: TextInputType.number),
        if (isEdit)
          BigButton(
            label: 'Delete medicine',
            secondary: true,
            icon: Icons.delete_outline_rounded,
            onTap: () async {
              final s2 = readStore(context);
              if (await confirmDialog(context, 'Delete ${widget.medicine!.name}?', 'Its reminders and history will be removed.')) {
                s2.deleteMedicine(widget.medicine!.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
      ],
    );
  }
}

// Keeps PillThumb reachable for form previews without a second import in callers.
Widget pillPreview(Medicine m) => PillThumb(m);
