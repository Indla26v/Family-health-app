import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../widgets/common.dart';

/// Enter a lab value by hand (parse failed, scanned report, or a missing row).
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key, required this.memberId, this.testKey, this.docId});
  final String memberId;
  final String? testKey;
  final String? docId;
  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late String testKey = widget.testKey ?? 'hba1c';
  final value = TextEditingController();
  final lab = TextEditingController();
  DateTime date = DateTime.now();
  int added = 0;

  @override
  void dispose() {
    value.dispose();
    lab.dispose();
    super.dispose();
  }

  void _save({required bool another}) {
    final v = double.tryParse(value.text);
    if (v == null) {
      toast(context, 'Enter the value as a number', ok: false);
      return;
    }
    final s = readStore(context);
    final t = testByKey(testKey)!;
    var doc = s.doc(widget.docId);
    doc ??= Doc(id: s.newId('doc'), memberId: widget.memberId, lab: lab.text.trim().isEmpty ? 'Entered by hand' : lab.text.trim(), date: date, kind: DocKind.lab, status: DocStatus.parsed, testCount: 0);
    final isNewDoc = s.doc(doc.id) == null;
    final r = LabResult(id: s.newId('lab'), memberId: widget.memberId, testKey: t.key, value: v, unit: t.unit, date: doc.date, docId: doc.id, lab: doc.lab, rawName: 'Entered by hand');
    if (isNewDoc) {
      doc.testCount = 1;
      s.addDoc(doc, [r]);
    } else {
      s.labs.add(r);
      doc.testCount = s.labsOfDoc(doc.id).length;
      s.changed();
    }
    added++;
    if (another) {
      value.clear();
      toast(context, 'Saved ${t.name}. Add another.', ok: true);
      setState(() {});
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = s.member(widget.memberId);
    final t = testByKey(testKey)!;
    final existing = s.doc(widget.docId);

    return PageBody(
      header: ScreenHeader(title: 'Enter a value', subtitle: '${m?.name ?? ''}${existing == null ? '' : ' · ${existing.lab}'}', back: true),
      spacing: 18,
      bottom: Row(children: [
        Expanded(child: BigButton(label: 'Save and add another', secondary: true, onTap: () => _save(another: true))),
        const SizedBox(width: 10),
        Expanded(child: BigButton(label: added > 0 ? 'Save & done' : 'Save', onTap: () => _save(another: false))),
      ]),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Test', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: testKey,
            isExpanded: true,
            decoration: const InputDecoration(),
            style: TextStyle(fontSize: 16, color: c.text),
            items: [for (final x in labTests) DropdownMenuItem(value: x.key, child: Text('${x.name} (${x.unit})', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => testKey = v ?? testKey),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Value (${t.unit})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: AppText.numberLarge,
            decoration: InputDecoration(hintText: 'e.g. ${t.high ?? t.low ?? 10}', suffixText: t.unit),
          ),
          const SizedBox(height: 4),
          Text('Usual range: ${t.refText(m?.sex ?? Sex.male)} ${t.unit}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
        ]),
        if (existing == null) ...[
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Date of the report', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (d != null) setState(() => date = d);
              },
              child: Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 20), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)), child: Row(children: [Expanded(child: Text(fmtDate(date), style: const TextStyle(fontSize: 16))), Icon(Icons.calendar_month_rounded, color: c.textSecondary)])),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Lab or hospital (optional)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary)),
            const SizedBox(height: 6),
            TextField(controller: lab, style: const TextStyle(fontSize: 16), textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Name of the lab')),
          ]),
        ],
      ],
    );
  }
}
