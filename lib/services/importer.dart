import 'dart:io' show Directory, File;
import 'dart:math' show max;

import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdfw;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'ocr.dart';
import 'parser.dart';

/// Reads report files on the phone. PDFs with a text layer (most lab PDFs) are
/// read directly; photos and camera scans are read with on-device OCR.
class ImportService {
  /// Web has no app folder, so files are kept in memory for the session only.
  static final Map<String, Uint8List> memory = {};

  static bool isPdf(String name) => name.toLowerCase().endsWith('.pdf');

  static Future<ExtractedReport> read(Uint8List bytes, String name) async {
    if (!isPdf(name)) return readPhotos([bytes]);
    PdfDocument? doc;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openData(bytes, sourceName: name);
      final buf = StringBuffer();
      for (final p in doc.pages) {
        final t = await p.loadStructuredText();
        buf.writeln(t.fullText);
      }
      final report = ReportParser.parse(buf.toString(), pages: doc.pages.length);
      if (report.tests.isNotEmpty || !Ocr.supported) return report;
      // No text layer (a scan saved as PDF, including this app's own camera scans):
      // render each page and read it with OCR instead.
      final texts = <String>[];
      final turns = <int>[];
      for (final p in doc.pages.take(20)) {
        final png = await _renderPng(p);
        final r = png == null ? null : await Ocr.readPage(png, prefer: turns.isEmpty ? 0 : turns.last);
        texts.add(r?.text ?? '');
        turns.add(r?.turns ?? 0);
      }
      final ocr = ReportParser.parse(texts.join('\n'), pages: doc.pages.length);
      if (ocr.tests.isEmpty) return report;
      return _photo(ocr, upright: await _turnPages(doc, turns));
    } catch (e) {
      debugPrint('PDF read failed for $name: $e');
      return ExtractedReport(lab: 'Lab report', date: null, patientName: null, tests: [], pages: 1, text: '');
    } finally {
      await doc?.dispose();
    }
  }

  /// A PDF page as a PNG [width] px wide (2000 is enough for OCR), on white.
  static Future<Uint8List?> _renderPng(PdfPage p, {double width = 2000}) async {
    final scale = width / p.width;
    final w = (p.width * scale).round(), h = (p.height * scale).round();
    final img = await p.render(width: w, height: h, fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xffffffff);
    if (img == null) return null;
    try {
      final ui = await img.createImage();
      try {
        return (await ui.toByteData(format: ImageByteFormat.png))?.buffer.asUint8List();
      } finally {
        ui.dispose();
      }
    } finally {
      img.dispose();
    }
  }

  /// Reads photographed pages (one report) with OCR, all pages together. When a
  /// page was the wrong way round, [ExtractedReport.upright] is the scan as a PDF
  /// with every page upright.
  static Future<ExtractedReport> readPhotos(List<Uint8List> pages) async {
    final texts = <String>[];
    final turns = <int>[];
    for (final p in pages) {
      final r = await Ocr.readPage(p, prefer: turns.isEmpty ? 0 : turns.last);
      texts.add(r.text);
      turns.add(r.turns);
    }
    final report = ReportParser.parse(texts.join('\n'), pages: pages.length);
    Uint8List? upright;
    if (turns.any((t) => t != 0)) {
      PdfDocument? doc;
      try {
        await pdfrxFlutterInitialize();
        doc = await PdfDocument.openData(await pdfFromPhotos(pages), sourceName: 'scan.pdf');
        upright = await _turnPages(doc, turns);
      } catch (e) {
        debugPrint('Turning scan pages failed: $e');
      } finally {
        await doc?.dispose();
      }
    }
    return _photo(report, upright: upright);
  }

  /// [doc] with page i turned [turns][i] quarter turns clockwise (only the page's
  /// rotation changes, the images aren't re-encoded); null when nothing turns.
  static Future<Uint8List?> _turnPages(PdfDocument doc, List<int> turns) async {
    if (!turns.any((t) => t != 0)) return null;
    try {
      final pages = doc.pages;
      doc.pages = [for (var i = 0; i < pages.length; i++) i < turns.length && turns[i] != 0 ? pages[i].rotatedBy(PdfPageRotation.values[turns[i] & 3]) : pages[i]];
      return await doc.encodePdf();
    } catch (e) {
      debugPrint('Turning PDF pages failed: $e');
      return null;
    }
  }

  static ExtractedReport _photo(ExtractedReport r, {Uint8List? upright}) =>
      ExtractedReport(lab: r.lab, date: r.date, patientName: r.patientName, tests: r.tests, pages: r.pages, text: r.text, fromPhoto: true, upright: upright);

  /// Combines photographed pages into one PDF (A4, one photo per page), so a scan
  /// is kept, shown and synced like any PDF report. Each photo is stored as a JPEG
  /// at most [kStoreSide] px long (about 0.25 MB a page; reading uses the full
  /// photos), so a long scan stays under the website's upload limit.
  static Future<Uint8List> pdfFromPhotos(List<Uint8List> pages, {bool shrink = true}) async {
    final doc = pw.Document(title: 'Scanned report');
    for (final p in pages) {
      final img = pw.MemoryImage(shrink ? await compactImage(p) : p);
      doc.addPage(pw.Page(pageFormat: pdfw.PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))));
    }
    return doc.save();
  }

  /// Longest side of a stored scan page, in pixels: sharp on any screen, small to sync.
  static const kStoreSide = 1600;

  /// The largest file the website accepts in one request (its host's limit is ~4.5 MB).
  static const kMaxUpload = 4 * 1024 * 1024;

  /// A photo as a JPEG at most [kStoreSide] px on its long side (the photo itself
  /// when it can't be decoded). Runs off the UI thread.
  static Future<Uint8List> compactImage(Uint8List bytes) => compute(_compactImage, bytes);

  static Uint8List _compactImage(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      var im = img.bakeOrientation(decoded);
      if (max(im.width, im.height) > kStoreSide) {
        im = im.width >= im.height ? img.copyResize(im, width: kStoreSide, interpolation: img.Interpolation.average) : img.copyResize(im, height: kStoreSide, interpolation: img.Interpolation.average);
      }
      return img.encodeJpg(im, quality: 72);
    } catch (_) {
      return bytes; // not an image this can read: keep it as it is
    }
  }

  /// A smaller copy of a big scanned PDF, to send to the website: every page
  /// rendered (upright) and stored as a compact JPEG. Null when it can't be made.
  static Future<Uint8List?> compactPdf(Uint8List bytes) async {
    PdfDocument? doc;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openData(bytes, sourceName: 'compact.pdf');
      final pages = <Uint8List>[];
      for (final p in doc.pages) {
        final png = await _renderPng(p, width: kStoreSide * p.width / max(p.width, p.height));
        if (png == null) return null;
        pages.add(await compactImage(png));
      }
      return await pdfFromPhotos(pages, shrink: false);
    } catch (e) {
      debugPrint('Making a smaller copy failed: $e');
      return null;
    } finally {
      await doc?.dispose();
    }
  }

  /// Copies a report into the app's private folder; returns its path (null on web).
  static Future<String?> persist(Uint8List bytes, String docId, String name) async {
    if (kIsWeb) {
      memory[docId] = bytes;
      return null;
    }
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/reports');
    await dir.create(recursive: true);
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';
    final f = File('${dir.path}/$docId.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// Removes every stored report file (used by "Delete everything").
  static Future<void> wipe() async {
    memory.clear();
    if (kIsWeb) return;
    try {
      final root = (await getApplicationDocumentsDirectory()).path;
      for (final d in ['reports', 'pills']) {
        final dir = Directory('$root/$d');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('ImportService.wipe failed: $e');
    }
  }

  static Future<Uint8List?> load(String docId, String? path) async {
    if (kIsWeb) return memory[docId];
    if (path == null) return null;
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }
}
