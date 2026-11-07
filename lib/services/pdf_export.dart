import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/store.dart';

const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _d(DateTime d) => '${d.day} ${_mo[d.month - 1]} ${d.year}';
String _t(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _clean(String s) => s.replaceAll('µ', 'u').replaceAll('–', '-').replaceAll('—', '-').replaceAll('’', "'").replaceAll('“', '"').replaceAll('”', '"');

pw.Widget _h(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 14, bottom: 6), child: pw.Text(t, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));

/// Health summary for a doctor visit: profile, medicines, latest results and readings.
Future<Uint8List> buildSummaryPdf(AppStore s, Member m) async {
  final doc = pw.Document(title: 'Health summary - ${m.name}');
  final meds = s.medsOf(m.id);
  final keys = {for (final l in s.labs.where((l) => l.memberId == m.id && l.confirmed)) l.testKey}.toList();
  final bp = s.latestVital(m.id, VitalType.bp);
  final sugar = s.latestVital(m.id, VitalType.sugar, afterMeal: false);
  final weight = s.latestVital(m.id, VitalType.weight);
  final appts = s.upcomingAppts(m.id);

  String food(Food f) => switch (f) { Food.before => 'before food', Food.after => 'after food', Food.any => '' };

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => [
      pw.Text('Health summary', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.Text('${m.fullName.isEmpty ? m.name : m.fullName} - ${m.age} years - blood group ${m.bloodGroup.isEmpty ? 'not known' : m.bloodGroup}', style: const pw.TextStyle(fontSize: 12)),
      pw.Text('Prepared ${_d(DateTime.now())} from records kept on this phone. Not medical advice.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      _h('Conditions'),
      pw.Text(m.conditions.isEmpty ? 'None listed' : m.conditions.map((c) => conditionById(c).en).join(', ')),
      _h('Allergies'),
      pw.Text(m.allergies.isEmpty ? 'None recorded' : m.allergies),
      _h('Current medicines'),
      if (meds.isEmpty) pw.Text('None recorded'),
      for (final x in meds) pw.Text('- ${x.label}: ${x.times.map((t) => _t(DateTime(2000, 1, 1, t.hour, t.minute))).join(', ')} ${food(x.food)}'),
      _h('Latest readings'),
      pw.Text('Blood pressure: ${bp == null ? '-' : '${bp.a.round()}/${bp.b.round()} mmHg (${VitalRanges.ofVital(bp).word}, ${_d(bp.at)})'}'),
      pw.Text('Sugar before breakfast: ${sugar == null ? '-' : '${sugar.a.round()} mg/dL (${VitalRanges.ofVital(sugar).word}, ${_d(sugar.at)})'}'),
      pw.Text('Weight: ${weight == null ? '-' : '${weight.a.toStringAsFixed(2)} kg (${_d(weight.at)})'}'),
      _h('Latest lab results'),
      if (keys.isEmpty)
        pw.Text('No results recorded')
      else
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headers: ['Test', 'Latest', 'Date', 'Lab', 'Status', 'Earlier values'],
          data: [
            for (final k in keys)
              () {
                final t = testByKey(k)!;
                final r = s.resultsOf(m.id, k);
                final last = r.last;
                final prev = r.reversed.skip(1).take(3).map((x) => fmtVal(t, x.value)).join(', ');
                return [_clean(t.name), _clean('${fmtVal(t, last.value)} ${t.unit}'), _d(last.date), _clean(last.lab), labStatus(t, last.value, m.sex).word, prev.isEmpty ? '-' : prev];
              }(),
          ],
        ),
      if (appts.isNotEmpty) ...[
        _h('Next appointment'),
        pw.Text(_clean('${appts.first.title}${appts.first.place.isEmpty ? '' : ', ${appts.first.place}'} - ${_d(appts.first.at)} ${_t(appts.first.at)}${appts.first.reason.isEmpty ? '' : ' (${appts.first.reason})'}')),
      ],
    ],
  ));
  return doc.save();
}

/// One-page emergency card.
Future<Uint8List> buildEmergencyPdf(AppStore s, Member m) async {
  final doc = pw.Document(title: 'Emergency card - ${m.name}');
  final meds = s.medsOf(m.id);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 2), borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('MEDICAL EMERGENCY', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(_clean(m.fullName.isEmpty ? m.name : m.fullName), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text('${m.age} years - Blood group ${m.bloodGroup.isEmpty ? 'not known' : m.bloodGroup}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        _h('Conditions'),
        pw.Text(m.conditions.isEmpty ? 'None listed' : m.conditions.map((c) => conditionById(c).en).join(', ')),
        _h('Current medicines'),
        pw.Text(meds.isEmpty ? 'None' : meds.map((x) => x.label).join(', ')),
        _h('Allergies'),
        pw.Text(m.allergies.isEmpty ? 'None recorded' : _clean(m.allergies)),
        _h('Emergency contacts'),
        for (final c in m.contacts) pw.Text(_clean('${c.name} (${c.relation}): ${c.phone.isEmpty ? '-' : c.phone}')),
      ]),
    ),
  ));
  return doc.save();
}

/// Plain text carried in the emergency QR code. Readable with any QR scanner, offline.
String emergencyQrText(AppStore s, Member m) {
  final meds = s.medsOf(m.id).map((x) => x.label).join(', ');
  final cond = m.conditions.map((c) => conditionById(c).en).join(', ');
  final contacts = m.contacts.where((c) => c.phone.isNotEmpty).map((c) => '${c.name} ${c.phone}').join('; ');
  return [
    'EMERGENCY - ${m.fullName.isEmpty ? m.name : m.fullName}',
    'Age ${m.age}, Blood ${m.bloodGroup.isEmpty ? 'not known' : m.bloodGroup}',
    if (cond.isNotEmpty) 'Conditions: $cond',
    if (meds.isNotEmpty) 'Medicines: $meds',
    'Allergies: ${m.allergies.isEmpty ? 'none recorded' : m.allergies}',
    if (contacts.isNotEmpty) 'Call: $contacts',
  ].join('\n');
}
