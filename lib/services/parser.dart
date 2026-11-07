import 'dart:typed_data';

import '../data/catalog.dart';
import '../data/models.dart';

class ExtractedTest {
  ExtractedTest({
    required this.testKey,
    required this.rawName,
    required this.value,
    required this.unit,
    required this.refText,
    required this.confidence,
    this.note = '',
  });
  final String testKey, rawName, unit, refText, note;
  final double value;
  final double confidence;
}

class ExtractedReport {
  ExtractedReport({required this.lab, required this.date, required this.patientName, required this.tests, required this.pages, required this.text, this.fromPhoto = false, this.upright});
  final String lab;

  /// Read from a photo or scan (OCR): its values always wait for a human check.
  final bool fromPhoto;

  /// The file again with sideways or upside-down pages turned upright (a scan
  /// photographed the wrong way round); null when every page already was.
  final Uint8List? upright;
  final DateTime? date;
  final String? patientName;
  final List<ExtractedTest> tests;
  final int pages;
  final String text;
}

const _knownLabs = <String, String>{
  'vijaya': 'Vijaya Diagnostics',
  'thyrocare': 'Thyrocare',
  'apollo': 'Apollo Clinic',
  'lal path': 'Dr Lal PathLabs',
  'metropolis': 'Metropolis',
  'srl': 'SRL Diagnostics',
  'redcliffe': 'Redcliffe Labs',
  'neuberg': 'Neuberg Diagnostics',
  'medall': 'Medall',
  'healthians': 'Healthians',
  'tata 1mg': 'Tata 1mg Labs',
  'svims': 'SVIMS',
  'krsna': 'Krsnaa Diagnostics',
};

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

// "ulU/mL" is how some lab PDFs spell µIU/mL (a lower-case L standing in for the I).
final _unitRe = RegExp(r'([µμu]\s*[lI]U\s*/\s*m[lL]|mg\s*/\s*d[lL]|g\s*/\s*d[lL]|[µμ]?\s*[uU]?IU\s*/\s*m[lL]|m\s*I?U\s*/\s*[lL]|ng\s*/\s*m[lL]|pg\s*/\s*m[lL]|ng\s*/\s*d[lL]|[µμu]g\s*/\s*d[lL]|[µμu]g\s*/\s*[lL]|[nmpµμu]mol\s*/\s*[lL]|mEq\s*/\s*[lL]|U\s*/\s*[lL]|IU\s*/\s*[lL]|mg\s*/\s*[lL]|g\s*/\s*[lL]|%)', caseSensitive: false);
final _numRe = RegExp(r'(?<![\d.A-Za-z])(\d{1,5}(?:[.,]\d{1,3})?)(?![A-Za-z\d])');
final _rangeRe = RegExp(r'(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)|[<>≤≥]\s*=?\s*\d+(?:\.\d+)?');

String _canonUnit(String u) => u.toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp('[µμ]'), 'u');

/// Keeps converted values free of float noise (0.83 × 100 = 83.00000000000001)
/// without rounding away any digit the lab printed.
double _round4(double v) => (v * 1e4).roundToDouble() / 1e4;

/// "H D L CHOLESTEROL" → "HDL CHOLESTEROL", so letter-spaced test names still match.
String _joinLetters(String l) =>
    l.replaceAllMapped(RegExp(r'(?<![A-Za-z.])[A-Za-z](?: [A-Za-z](?![A-Za-z.]))+'), (m) => m.group(0)!.replaceAll(' ', ''));

/// Turns the text of a lab report into canonical test values with a confidence
/// score. Anything uncertain is flagged so the review screen can ask the user.
class ReportParser {
  static final List<(String, String, RegExp)> _aliases = _build();

  static List<(String, String, RegExp)> _build() {
    final out = <(String, String, RegExp)>[];
    for (final t in labTests) {
      for (final a in t.aliases) {
        // "Non HDL cholesterol" is a different number from HDL cholesterol.
        out.add((t.key, a, RegExp('(?<!non[\\s-]*)(?<![a-z0-9])${RegExp.escape(a).replaceAll(' ', r'\s*')}(?![a-z0-9])', caseSensitive: false)));
      }
    }
    out.sort((a, b) => b.$2.length.compareTo(a.$2.length));
    return out;
  }

  static ExtractedReport parse(String text, {int pages = 1}) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim()).map(_joinLetters).where((l) => l.isNotEmpty).toList();
    final found = <String, ExtractedTest>{};

    for (final line in lines) {
      final low = line.toLowerCase();
      if (low.contains('ratio') || low.contains('reference') && !RegExp(r'\d').hasMatch(low)) continue;
      for (final (key, _, re) in _aliases) {
        if (found.containsKey(key)) continue;
        final m = re.firstMatch(low);
        if (m == null) continue;
        final def = testByKey(key)!;
        final rest = line.substring(m.end);
        // The first number that is not part of a "< 100" style range.
        RegExpMatch? nm;
        for (final c in _numRe.allMatches(rest)) {
          final before = rest.substring(0, c.start).trimRight();
          if (before.endsWith('<') || before.endsWith('>') || before.endsWith('-') || before.endsWith('–')) continue;
          // The first number of "70 - 100" is the reference range, not the result.
          if (RegExp(r'^\s*(?:-|–|to\s)\s*\d').hasMatch(rest.substring(c.end))) continue;
          nm = c;
          break;
        }
        if (nm == null) continue;
        var value = double.tryParse(nm.group(1)!.replaceAll(',', '.'));
        if (value == null) continue;
        final after = rest.substring(nm.end);
        final um = _unitRe.firstMatch(after);
        var unit = um?.group(0)?.replaceAll(RegExp(r'\s+'), '') ?? '';
        var ref = _rangeRe.firstMatch(after)?.group(0)?.trim() ?? '';
        var conf = 0.96;
        var note = '';
        var rawName = line.substring(m.start, m.end).trim();
        if (unit.isEmpty) {
          unit = def.unit;
          conf = 0.72;
          note = 'Unit was unclear on the page — please check';
        } else if (_canonUnit(unit) != _canonUnit(def.unit)) {
          // Known units are converted (value and reference range alike), so every
          // reading of a test is stored and charted in the same unit.
          final f = def.conv[_canonUnit(unit)];
          if (f == null) {
            conf = 0.62;
            note = 'Unit on the page ($unit) differs from the usual ${def.unit} — please check';
          } else if (f != 1) {
            // An exact conversion needs no review; keep what the lab printed alongside.
            rawName += ' (${nm.group(1)} $unit on report)';
            value = _round4(value * f);
            ref = ref.replaceAllMapped(RegExp(r'\d+(?:\.\d+)?'), (n) => fmtNum(double.parse(n.group(0)!) * f, def.decimals));
          }
          unit = def.unit;
        }
        if (!def.plausible(value)) {
          conf = 0.45;
          note = 'This value looks unusual — please check';
        }
        found[key] = ExtractedTest(
          testKey: key,
          rawName: rawName,
          value: value,
          unit: unit,
          refText: ref,
          confidence: conf,
          note: note,
        );
        break;
      }
    }

    return ExtractedReport(
      lab: _lab(lines, text),
      date: _date(lines),
      patientName: _patient(lines),
      tests: found.values.toList(),
      pages: pages,
      text: text,
    );
  }

  static String _lab(List<String> lines, String text) {
    final low = text.toLowerCase();
    for (final e in _knownLabs.entries) {
      if (low.contains(e.key)) return e.value;
    }
    return 'Lab report';
  }

  static String? _patient(List<String> lines) {
    final re = RegExp(r'(?:patient\s*name|name\s+of\s+patient|^name)\s*[:\-]\s*(.+)', caseSensitive: false);
    for (final l in lines.take(60)) {
      final m = re.firstMatch(l);
      if (m != null) {
        var n = m.group(1)!.trim();
        n = n.split(RegExp(r'\s{2,}|\bage\b|\bsex\b|\bgender\b', caseSensitive: false)).first.trim();
        n = n.replaceFirst(RegExp(r'^(mr|mrs|ms|miss|smt|sri|shri)\.?\s+', caseSensitive: false), '');
        if (n.isNotEmpty) return n;
      }
    }
    return null;
  }

  static DateTime? _date(List<String> lines) {
    final numeric = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');
    final named = RegExp(r'\b(\d{1,2})[\s\-]*(jan|feb|mar|apr|may|jun|jul|aug|sept|sep|oct|nov|dec)[a-z]*[\s\-,.]*(\d{2,4})\b', caseSensitive: false);
    final isoDate = RegExp(r'\b(20\d{2})-(\d{1,2})-(\d{1,2})\b');
    DateTime? scan(String l) {
      final i = isoDate.firstMatch(l);
      if (i != null) {
        final y = int.parse(i.group(1)!), mo = int.parse(i.group(2)!), d = int.parse(i.group(3)!);
        if (_valid(y, mo, d)) return DateTime(y, mo, d);
      }
      final n = named.firstMatch(l);
      if (n != null) {
        final y = _year(n.group(3)!);
        final d = int.parse(n.group(1)!);
        final mo = _months[n.group(2)!.toLowerCase()]!;
        if (_valid(y, mo, d)) return DateTime(y, mo, d);
      }
      final m = numeric.firstMatch(l);
      if (m != null) {
        final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = _year(m.group(3)!);
        if (_valid(y, mo, d)) return DateTime(y, mo, d);
      }
      return null;
    }

    for (final key in ['collected', 'collection', 'sample', 'reported', 'report date', 'registered', 'date']) {
      for (final l in lines) {
        if (l.toLowerCase().contains(key)) {
          final d = scan(l);
          if (d != null) return d;
        }
      }
    }
    for (final l in lines.take(80)) {
      final d = scan(l);
      if (d != null) return d;
    }
    return null;
  }

  static int _year(String s) {
    final y = int.parse(s);
    return y < 100 ? 2000 + y : y;
  }

  static bool _valid(int y, int mo, int d) => y >= 2000 && y <= DateTime.now().year + 1 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31;

  /// Does the patient name on the page look like this family member?
  static bool nameMatches(String? patient, Member m) {
    if (patient == null) return false;
    final p = patient.toLowerCase();
    for (final n in [m.fullName, m.name]) {
      final t = n.trim().toLowerCase();
      if (t.isEmpty) continue;
      for (final part in t.split(RegExp(r'\s+'))) {
        if (part.length >= 3 && p.contains(part)) return true;
      }
    }
    return false;
  }
}
