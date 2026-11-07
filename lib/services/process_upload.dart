import 'dart:typed_data';

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'importer.dart';
import 'parser.dart';

class UploadOutcome {
  UploadOutcome({required this.doc, required this.total, required this.auto, required this.check, required this.patient, required this.nameMismatch, required this.pages});
  final Doc doc;
  final int total, auto, check, pages;
  final String? patient;
  final bool nameMismatch;
  bool get unreadable => total == 0;
}

/// Reads a report file, stores it, and saves the values: confident ones are
/// auto-confirmed, uncertain ones wait for review. If the patient's name on the
/// page doesn't match the chosen member, nothing is auto-confirmed.
///
/// [photos]: pages photographed with the scanner, read with OCR and stored as one PDF.
Future<UploadOutcome> processUpload(AppStore s, {required String memberId, required String fileName, required Uint8List bytes, Doc? retry, List<Uint8List>? photos}) async {
  final member = s.member(memberId)!;
  final report = photos != null && photos.isNotEmpty ? await ImportService.readPhotos(photos) : await ImportService.read(bytes, fileName);
  final docId = retry?.id ?? s.newId('doc');
  // Pages that were sideways are kept upright, so the report reads the right way round.
  final upright = report.upright;
  final name = upright != null && !ImportService.isPdf(fileName) ? 'scan.pdf' : fileName;
  final path = await ImportService.persist(upright ?? bytes, docId, name);
  final isImage = !ImportService.isPdf(name);
  // The stored file changed (pages turned): send it to the server again.
  if (upright != null) s.sync.uploadedFiles.remove(docId);
  // Reading again keeps a date set by hand when the page itself has none.
  final keptDate = report.date == null && retry != null && retry.note.isEmpty;
  final date = report.date ?? (keptDate ? retry.date : DateTime.now());
  final nameFound = report.patientName != null;
  final mismatch = nameFound && !ReportParser.nameMatches(report.patientName, member);

  if (retry != null) {
    s.labs.removeWhere((l) => l.docId == retry.id);
    s.docs.removeWhere((d) => d.id == retry.id);
  }

  final results = <LabResult>[];
  var auto = 0, check = 0;
  for (final t in report.tests) {
    // A photo can drop a decimal point (66.4 → 664), so photo readings always get a look.
    final ok = t.confidence >= 0.8 && !mismatch && !report.fromPhoto;
    if (ok) {
      auto++;
    } else {
      check++;
    }
    results.add(LabResult(
      id: s.newId('lab'),
      memberId: memberId,
      testKey: t.testKey,
      value: t.value,
      unit: t.unit,
      date: date,
      docId: docId,
      lab: report.lab,
      rawName: t.rawName,
      confidence: t.confidence,
      confirmed: ok,
      checkNote: mismatch
          ? 'Name on report (${report.patientName}) does not look like ${member.name}'
          : t.note.isNotEmpty
              ? t.note
              : report.fromPhoto
                  ? 'Read from a photo — compare with the report'
                  : '',
      refText: t.refText.isEmpty ? (testByKey(t.testKey)?.refText(member.sex) ?? '') : t.refText,
    ));
  }

  final status = results.isEmpty ? DocStatus.needsReview : (check > 0 ? DocStatus.needsReview : DocStatus.parsed);
  final doc = Doc(
    id: docId,
    memberId: memberId,
    lab: report.lab,
    date: date,
    kind: DocKind.lab,
    status: status,
    testCount: results.length,
    filePath: path,
    isImage: isImage,
    pages: report.pages,
    note: report.date == null && !keptDate ? 'Date not found on the report — please check' : '',
  );
  s.addDoc(doc, results);
  return UploadOutcome(doc: doc, total: results.length, auto: auto, check: check, patient: report.patientName, nameMismatch: mismatch, pages: report.pages);
}
