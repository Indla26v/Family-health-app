import 'dart:io' show File;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'parser.dart';

/// On-device text reading for photos and scans of paper reports (Google ML Kit;
/// nothing leaves the phone). The text is rebuilt into table rows so the same
/// [ReportParser] that reads PDFs can pick out the test values.
class Ocr {
  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Text of one photo, as rows like "HAEMOGLOBIN  12.3  g/dl  12.0 - 15.0". Empty when unsupported or unreadable.
  static Future<String> read(Uint8List bytes) async => (await readPage(bytes)).text;

  /// Reads one page and finds which way up it is.
  ///
  /// A page photographed sideways or upside down reads as gibberish, so when the
  /// photo as it is yields fewer than three tests, it is also read turned. The
  /// turn tried first is [prefer] (pages of one scan are usually all the same way
  /// round), then the one the slant of the recognised lines points to, then the
  /// rest. The turn that finds the most tests (then real words) wins; [turns] is
  /// how many quarter turns clockwise make the page upright.
  static Future<({String text, int turns})> readPage(Uint8List bytes, {int prefer = 0}) async {
    if (!supported) return (text: '', turns: 0);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final first = await _recognize(recognizer, bytes);
      var best = first.text;
      var bestTurns = 0;
      var bestScore = _score(best);
      final plain = bestScore;
      if (bestScore >= 3000) return (text: best, turns: 0);
      final order = <int>{if (prefer != 0) prefer, if (first.hint != 0) first.hint, 1, 3, 2};
      var i = 0;
      for (final turns in order) {
        final turned = await _rotate(bytes, turns);
        if (turned == null) continue;
        final text = (await _recognize(recognizer, turned)).text;
        final sc = _score(text);
        if (sc > bestScore) {
          best = text;
          bestScore = sc;
          bestTurns = turns;
        }
        if (sc >= 3000) break;
        // A page without tests (cover, address): stop once a likely turn reads clearly better.
        if (i++ == 0 && (prefer != 0 || first.hint != 0) && sc ~/ 1000 >= plain ~/ 1000 && sc % 1000 > 2 * (plain % 1000) + 20) break;
      }
      return (text: best, turns: bestTurns);
    } catch (e) {
      debugPrint('OCR failed: $e');
      return (text: '', turns: 0);
    } finally {
      await recognizer.close();
    }
  }

  /// How well a reading went: tests found (×1000), then words of 3+ letters.
  static int _score(String text) => ReportParser.parse(text).tests.length * 1000 + min(999, RegExp('[A-Za-z]{3,}').allMatches(text).length);

  /// The rows of one image, and a guess at the turn that would make it upright
  /// from the slant most lines share (0 when level or unclear).
  static Future<({String text, int hint})> _recognize(TextRecognizer recognizer, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.img');
    await f.writeAsBytes(bytes, flush: true);
    try {
      final r = await recognizer.processImage(InputImage.fromFilePath(f.path));
      final lines = [
        for (final b in r.blocks)
          for (final l in b.lines) OcrLine(l.text, l.boundingBox, l.cornerPoints.length == 4 ? atan2((l.cornerPoints[1].y - l.cornerPoints[0].y).toDouble(), (l.cornerPoints[1].x - l.cornerPoints[0].x).toDouble()) : null),
      ];
      return (text: rowsOf(lines), hint: uprightHint(lines));
    } finally {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Quarter turns clockwise suggested by the lines' slant: text running down the
  /// image needs 3, running up needs 1, upside down needs 2. 0 unless most lines agree.
  static int uprightHint(List<OcrLine> lines) {
    final votes = [0, 0, 0, 0];
    var n = 0;
    for (final l in lines) {
      final a = l.angle;
      if (a == null || l.text.trim().length < 3) continue;
      n++;
      // Quadrant of the reading direction: 0 → right, 1 → down, 2 → left, 3 → up.
      final q = ((a / (pi / 2)).round()) % 4;
      votes[q]++;
    }
    if (n < 5) return 0;
    const turnFor = [0, 3, 2, 1];
    for (var q = 1; q < 4; q++) {
      if (votes[q] > n * .6) return turnFor[q];
    }
    return 0;
  }

  /// The photo turned by [quarterTurns] × 90° clockwise (as PNG), at most 2400 px on its long side.
  static Future<Uint8List?> _rotate(Uint8List bytes, int quarterTurns) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    try {
      final scale = min(1.0, 2400 / max(img.width, img.height));
      final w = img.width * scale, h = img.height * scale;
      final (nw, nh) = quarterTurns.isOdd ? (h, w) : (w, h);
      final rec = ui.PictureRecorder();
      ui.Canvas(rec)
        ..translate(nw / 2, nh / 2)
        ..rotate(quarterTurns * pi / 2)
        ..translate(-w / 2, -h / 2)
        ..scale(scale)
        ..drawImage(img, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.medium);
      final out = await rec.endRecording().toImage(nw.round(), nh.round());
      try {
        return (await out.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
      } finally {
        out.dispose();
      }
    } finally {
      img.dispose();
    }
  }
}

/// One recognised line: its text, box, and the slant of its top edge (radians).
class OcrLine {
  const OcrLine(this.text, this.box, [this.angle]);
  final String text;
  final ui.Rect box;
  final double? angle;
}

/// Groups recognised lines into table rows. A report table comes back cell by
/// cell (name, value, unit and range are separate lines), and a hand-held photo
/// is rarely level: the page tilts, and curls a little differently down its
/// length. So:
///  1. the page's slope is fitted from the table (see below) and every line is
///     straightened with it (a shear: lines further right are lifted by their
///     distance × the slope);
///  2. test names (wordy lines starting in the left part of the page) anchor the
///     rows, and every other cell joins the name it sits closest to;
///  3. cells near no name (a right-hand header block) form rows among themselves.
String rowsOf(List<OcrLine> lines) {
  final ls = lines.where((l) => l.text.trim().isNotEmpty).toList();
  if (ls.isEmpty) return '';
  final heights = [for (final l in ls) l.box.height]..sort();
  final h = max(4.0, heights[heights.length ~/ 2]);
  final top = ls.map((l) => l.box.top).reduce(min), bottom = ls.map((l) => l.box.bottom).reduce(max);
  final left = ls.map((l) => l.box.left).reduce(min), right = ls.map((l) => l.box.right).reduce(max);

  // Local slope: median slant of wide lines within ±12% of the page height.
  final wide = [for (final l in ls) if (l.angle != null && l.box.width > 3 * l.box.height) l];
  double slopeAt(double y) {
    final win = (bottom - top) * .12;
    var near = [for (final l in wide) if ((l.box.center.dy - y).abs() <= win) l.angle!];
    if (near.length < 2) near = [for (final l in wide) l.angle!];
    if (near.isEmpty) return 0;
    near.sort();
    return tan(near[near.length ~/ 2]);
  }

  // A name starts with a letter or digit ("25 HYDROXY VITAMIN D"); ": Mrs. X" is a value.
  bool isName(OcrLine l) => l.box.left < left + (right - left) * .4 && RegExp(r'^\s*[A-Za-z0-9]').hasMatch(l.text) && RegExp('[A-Za-z]').allMatches(l.text).length >= 2;

  // ML Kit often reports a tilted line as level, so the slant of the lines alone
  // can't be trusted. Fit the slope from the table itself: the one that puts the
  // value cells closest to the names, starting from the lines' own slant and
  // preferring it when two fit equally (a whole-row shift also lines up).
  final nameLines = [for (final l in ls) if (isName(l)) l];
  final cellLines = [for (final l in ls) if (!isName(l)) l];
  final prior = slopeAt((top + bottom) / 2);
  double cost(double sl) {
    var c = (sl - prior).abs() * h * 4;
    for (final cl in cellLines) {
      final cy = cl.box.center.dy - (cl.box.center.dx - left) * sl;
      var best = h;
      for (final n in nameLines) {
        best = min(best, (n.box.center.dy - (n.box.center.dx - left) * sl - cy).abs());
      }
      c += best;
    }
    return c;
  }

  var slope = prior, bestCost = cost(prior);
  for (var i = -30; i <= 30; i++) {
    final c = cost(i * .002);
    if (c < bestCost - 1e-6) {
      bestCost = c;
      slope = i * .002;
    }
  }
  final items = [for (final l in ls) (line: l, x: l.box.center.dx, y: l.box.center.dy - (l.box.center.dx - left) * slope)];
  final names = [for (final it in items) if (isName(it.line)) it]..sort((a, b) => a.y.compareTo(b.y));
  final rows = <({double y, List<({OcrLine line, double x, double y})> cells})>[
    for (final n in names) (y: n.y, cells: [n]),
  ];
  final loose = <({OcrLine line, double x, double y})>[];
  for (final it in items) {
    if (isName(it.line)) continue;
    ({double y, List<({OcrLine line, double x, double y})> cells})? best;
    for (final r in rows) {
      if (best == null || (r.y - it.y).abs() < (best.y - it.y).abs()) best = r;
    }
    if (best != null && (best.y - it.y).abs() <= h * .8) {
      best.cells.add(it);
    } else {
      loose.add(it);
    }
  }
  // Cells that matched no name: group by height among themselves.
  loose.sort((a, b) => a.y.compareTo(b.y));
  var mean = 0.0;
  List<({OcrLine line, double x, double y})>? cur;
  for (final it in loose) {
    if (cur != null && (it.y - mean).abs() <= h * .6) {
      cur.add(it);
      mean += (it.y - mean) / cur.length;
    } else {
      cur = [it];
      mean = it.y;
      rows.add((y: it.y, cells: cur));
    }
  }
  rows.sort((a, b) => a.y.compareTo(b.y));
  return [
    for (final r in rows) (r.cells..sort((a, b) => a.x.compareTo(b.x))).map((e) => e.line.text.trim()).join('  '),
  ].join('\n');
}
