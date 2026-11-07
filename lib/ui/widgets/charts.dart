import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'common.dart';

/// One plotted value, traceable back to its source report.
class ChartPoint {
  ChartPoint(this.date, this.value, {this.lab = '', this.docId, this.outside = false, this.label});
  final DateTime date;
  final double value;
  final String lab;
  final String? docId;
  final bool outside;
  final String? label;
}

class ChartSeries {
  ChartSeries(this.points, this.color, {this.name = '', this.colourOutside = true});
  final List<ChartPoint> points;
  final Color color;
  final String name;
  final bool colourOutside;
}

class ChartBand {
  ChartBand(this.lo, this.hi, this.label);
  final double? lo, hi;
  final String label;
}

class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.color, this.width = 96, this.height = 32});
  final List<double> values;
  final Color? color;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExcludeSemantics(child: CustomPaint(size: Size(width, height), painter: _SparkPainter(values, color ?? c.accent)));
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color);
  final List<double> v;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    if (v.length < 2) {
      if (v.length == 1) canvas.drawCircle(Offset(s.width - 3, s.height / 2), 3, Paint()..color = color);
      return;
    }
    final lo = v.reduce(min), hi = v.reduce(max);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    Offset pt(int i) => Offset(3 + (s.width - 6) * i / (v.length - 1), 3 + (s.height - 6) * (1 - (v[i] - lo) / span));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(pt(v.length - 1), 3.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v || o.color != color;
}

enum Period { m3, m6, y1, all }

const _periodLabels = {Period.m3: '3M', Period.m6: '6M', Period.y1: '1Y', Period.all: 'All'};

DateTime? _cutoff(Period p) {
  final n = DateTime.now();
  return switch (p) {
    Period.m3 => DateTime(n.year, n.month - 3, n.day),
    Period.m6 => DateTime(n.year, n.month - 6, n.day),
    Period.y1 => DateTime(n.year - 1, n.month, n.day),
    Period.all => null,
  };
}

/// Line chart with period chips, a shaded reference band, out-of-range points
/// coloured, and tap-a-point to see value, date, lab and "View report".
///
/// Lab charts (no [cutoffOf]) offer All, 1Y and then each calendar year that has
/// results, newest first.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.series,
    this.band,
    this.moreBands = const [],
    this.targetLine,
    this.targetLabel,
    required this.unit,
    this.decimals = 1,
    this.summary = '',
    this.onViewReport,
    this.showPeriods = true,
    this.height = 210,
    this.initial = Period.all,
    this.periods = const [Period.all, Period.y1],
    this.periodLabelOf,
    this.cutoffOf,
  });
  final List<ChartSeries> series;
  final ChartBand? band;
  final List<ChartBand> moreBands;
  final double? targetLine;
  final String? targetLabel;
  final String unit, summary;
  final int decimals;
  final void Function(ChartPoint)? onViewReport;
  final bool showPeriods;
  final double height;
  final Period initial;
  final List<Period> periods;
  final String Function(Period)? periodLabelOf;
  final DateTime? Function(Period)? cutoffOf;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  /// A [Period], or a year (int).
  late Object period = widget.initial;
  (int, int)? sel; // (series, point)

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final years = widget.cutoffOf != null ? <int>[] : ({for (final s in widget.series) for (final p in s.points) p.date.year}.toList()..sort((a, b) => b - a));
    final p0 = period;
    final cut = p0 is Period ? (widget.cutoffOf ?? _cutoff)(p0) : null;
    bool keep(ChartPoint p) => p0 is int ? p.date.year == p0 : (cut == null || !p.date.isBefore(cut));
    final series = [
      for (final s in widget.series) ChartSeries([for (final p in s.points) if (keep(p)) p], s.color, name: s.name, colourOutside: s.colourOutside)
    ];
    final total = series.fold<int>(0, (a, s) => a + s.points.length);
    final sp = sel != null && sel!.$1 < series.length && sel!.$2 < series[sel!.$1].points.length ? series[sel!.$1].points[sel!.$2] : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.showPeriods) ...[
        ChoiceChips<Object>(
          options: [
            for (final p in widget.periods) (p, widget.periodLabelOf?.call(p) ?? _periodLabels[p]!),
            if (years.length > 1)
              for (final y in years) (y, '$y'),
          ],
          value: period,
          onChanged: (p) => setState(() {
            period = p;
            sel = null;
          }),
        ),
        const SizedBox(height: 12),
      ],
      if (total == 0)
        SizedBox(height: widget.height, child: Center(child: Text('No results in this period', style: TextStyle(fontSize: 15, color: c.textSecondary))))
      else
        Semantics(
          label: widget.summary,
          child: LayoutBuilder(builder: (context, box) {
            final bands = [if (widget.band != null) widget.band!, ...widget.moreBands];
            final geo = _Geo(series, bands, widget.targetLine, Size(box.maxWidth, widget.height));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final hit = geo.nearest(d.localPosition);
                setState(() => sel = hit);
              },
              child: CustomPaint(
                size: Size(box.maxWidth, widget.height),
                painter: _ChartPainter(geo: geo, pal: c, sel: sel, bands: bands, target: widget.targetLine, targetLabel: widget.targetLabel, decimals: widget.decimals),
              ),
            );
          }),
        ),
      if (sp != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: sp.label ?? sp.value.toStringAsFixed(widget.decimals), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  TextSpan(text: ' ${widget.unit}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
                ])),
                Text('${fmtDate(sp.date)}${sp.lab.isEmpty ? '' : ' · ${sp.lab}'}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              ]),
            ),
            if (widget.onViewReport != null && sp.docId != null) TextLink('View report', icon: Icons.description_rounded, onTap: () => widget.onViewReport!(sp)),
          ]),
        ),
      ],
    ]);
  }
}

class _Geo {
  _Geo(this.series, List<ChartBand> bands, double? target, this.size) {
    final xs = <double>[], ys = <double>[];
    for (final s in series) {
      for (final p in s.points) {
        xs.add(p.date.millisecondsSinceEpoch.toDouble());
        ys.add(p.value);
      }
    }
    for (final b in bands) {
      if (b.lo != null) ys.add(b.lo!);
      if (b.hi != null) ys.add(b.hi!);
    }
    if (target != null) ys.add(target);
    var xmin = xs.reduce(min), xmax = xs.reduce(max);
    if (xmax - xmin < 86400000 * 3) {
      xmin -= 86400000 * 3;
      xmax += 86400000 * 3;
    }
    final pad = (xmax - xmin) * .02;
    xMin = xmin - pad;
    xMax = xmax + pad;
    var lo = ys.reduce(min), hi = ys.reduce(max);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    final span = hi - lo;
    lo -= span * .12;
    hi += span * .16;
    final step = _niceStep((hi - lo) / 4);
    yMin = (lo / step).floor() * step;
    yMax = (hi / step).ceil() * step;
    yStep = step;
  }
  final List<ChartSeries> series;
  final Size size;
  late final double xMin, xMax, yMin, yMax, yStep;
  static const left = 40.0, right = 12.0, top = 12.0, bottom = 28.0;

  double x(DateTime d) => left + (size.width - left - right) * ((d.millisecondsSinceEpoch - xMin) / (xMax - xMin));
  double y(double v) => top + (size.height - top - bottom) * (1 - (v - yMin) / (yMax - yMin));

  (int, int)? nearest(Offset o) {
    (int, int)? best;
    var bd = 36.0;
    for (var si = 0; si < series.length; si++) {
      for (var pi = 0; pi < series[si].points.length; pi++) {
        final p = series[si].points[pi];
        final d = (Offset(x(p.date), y(p.value)) - o).distance;
        if (d < bd) {
          bd = d;
          best = (si, pi);
        }
      }
    }
    return best;
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final e = pow(10, (log(raw) / ln10).floor()).toDouble();
    final f = raw / e;
    final n = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
    return n * e;
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.geo, required this.pal, required this.sel, required this.bands, required this.target, required this.targetLabel, required this.decimals});
  final _Geo geo;
  final AppPalette pal;
  final (int, int)? sel;
  final List<ChartBand> bands;
  final double? target;
  final String? targetLabel;
  final int decimals;

  void _text(Canvas canvas, String t, Offset at, {double size = 13, Color? color, FontWeight w = FontWeight.w400, TextAlign align = TextAlign.left, bool baselineMid = false}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color ?? pal.textSecondary, fontWeight: w)), textDirection: TextDirection.ltr)..layout();
    var dx = at.dx;
    if (align == TextAlign.right) dx -= tp.width;
    if (align == TextAlign.center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, baselineMid ? at.dy - tp.height / 2 : at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = pal.border..strokeWidth = 1;
    // y grid + labels
    for (var v = geo.yMin; v <= geo.yMax + geo.yStep / 2; v += geo.yStep) {
      final y = geo.y(v);
      canvas.drawLine(Offset(_Geo.left, y), Offset(size.width - _Geo.right, y), grid);
      final label = geo.yStep >= 1 ? v.round().toString() : v.toStringAsFixed(geo.yStep < .1 ? 2 : 1);
      _text(canvas, label, Offset(_Geo.left - 8, y), size: 13, align: TextAlign.right, baselineMid: true);
    }
    // reference bands
    for (final band in bands) {
      if (band.lo == null && band.hi == null) continue;
      final top = geo.y(band.hi ?? geo.yMax);
      final bot = geo.y(band.lo ?? geo.yMin);
      canvas.drawRect(Rect.fromLTRB(_Geo.left, top, size.width - _Geo.right, bot), Paint()..color = pal.ok.withValues(alpha: .10));
      if (band.label.isNotEmpty) _text(canvas, band.label, Offset(size.width - _Geo.right - 4, (band.hi != null ? bot : top) + (band.hi != null ? -17 : 3)), size: 13, color: pal.ok, w: FontWeight.w600, align: TextAlign.right);
    }
    if (target != null) {
      final y = geo.y(target!);
      final dash = Paint()..color = pal.accent.withValues(alpha: .6)..strokeWidth = 1.5;
      for (var x = _Geo.left; x < size.width - _Geo.right; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(min(x + 5, size.width - _Geo.right), y), dash);
      }
      if (targetLabel != null) _text(canvas, targetLabel!, Offset(_Geo.left + 4, y - 17), size: 13, color: pal.accent, w: FontWeight.w600);
    }
    // x ticks
    for (final t in _xTicks()) {
      final x = geo.x(t.$1);
      if (x < _Geo.left - 2 || x > size.width - _Geo.right + 2) continue;
      _text(canvas, t.$2, Offset(x, size.height - 20), size: 13, align: TextAlign.center);
    }
    // series
    for (final s in geo.series) {
      if (s.points.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final o = Offset(geo.x(s.points[i].date), geo.y(s.points[i].value));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, Paint()..color = s.color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      final dots = s.points.length <= 40;
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final o = Offset(geo.x(p.date), geo.y(p.value));
        final isSel = sel != null && geo.series.indexOf(s) == sel!.$1 && sel!.$2 == i;
        if (!dots && !isSel) continue;
        final col = p.outside && s.colourOutside ? pal.danger : s.color;
        canvas.drawCircle(o, isSel ? 8 : 5, Paint()..color = pal.surface);
        canvas.drawCircle(o, isSel ? 6.5 : 4, Paint()..color = col);
        // Outside-range points also get a ring so colour is never the only cue.
        if (p.outside && s.colourOutside) canvas.drawCircle(o, isSel ? 9.5 : 7, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
    }
  }

  List<(DateTime, String)> _xTicks() {
    final a = DateTime.fromMillisecondsSinceEpoch(geo.xMin.toInt()), b = DateTime.fromMillisecondsSinceEpoch(geo.xMax.toInt());
    final days = b.difference(a).inDays;
    final out = <(DateTime, String)>[];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (days > 900) {
      final step = days > 3200 ? 2 : 1;
      for (var y = a.year + 1; y <= b.year; y += step) {
        out.add((DateTime(y), '$y'));
      }
      if (out.isEmpty) out.add((a, '${a.year}'));
    } else if (days > 150) {
      var d = DateTime(a.year, a.month + 1);
      final every = days > 500 ? 4 : 2;
      var i = 0;
      while (d.isBefore(b)) {
        if (i % every == 0) out.add((d, '${mo[d.month - 1]} ${d.year % 100}'));
        d = DateTime(d.year, d.month + 1);
        i++;
      }
    } else {
      final n = days > 60 ? 4 : 5;
      for (var i = 0; i <= n; i++) {
        final d = a.add(Duration(days: (days * i / n).round()));
        out.add((d, '${d.day} ${mo[d.month - 1]}'));
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.sel != sel || o.geo != geo || o.pal != pal;
}

/// Month grid for adherence. Cells: green (all taken), amber (1 missed), red (2+), empty.
class AdherenceGrid extends StatelessWidget {
  const AdherenceGrid({super.key, required this.month, required this.data});
  final DateTime month;
  final Map<int, (int, int)> data; // day -> (expected, taken)
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final cells = <Widget>[];
    for (final h in ['M', 'T', 'W', 'T', 'F', 'S', 'S']) {
      cells.add(Center(child: Text(h, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textSecondary))));
    }
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= days; d++) {
      final e = data[d];
      Color bg = c.surfaceAlt, fg = c.textSecondary;
      String mark = '';
      String sem = 'No data';
      if (e != null) {
        final missed = e.$1 - e.$2;
        if (missed <= 0) {
          bg = c.okTint;
          fg = c.ok;
          sem = 'All taken';
        } else if (missed == 1) {
          bg = c.warnTint;
          fg = c.warn;
          mark = '!';
          sem = '1 missed';
        } else {
          bg = c.dangerTint;
          fg = c.danger;
          mark = '×';
          sem = '$missed missed';
        }
      }
      cells.add(Semantics(
        label: '$d ${monthName(month.month)}: $sem',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Stack(children: [
            Center(child: Text('$d', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: e == null ? c.textSecondary : c.text))),
            if (mark.isNotEmpty) Positioned(top: 1, right: 4, child: Text(mark, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg))),
          ]),
        ),
      ));
    }
    return GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1, children: cells);
  }
}

/// Small colour-chip legend that also names the state in words.
class LegendDot extends StatelessWidget {
  const LegendDot(this.color, this.label, {super.key, this.mark = ''});
  final Color color;
  final String label, mark;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 18, height: 18, alignment: Alignment.center, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)), child: Text(mark, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
      const SizedBox(width: 6),
      Text(tr(label), style: const TextStyle(fontSize: 14)),
    ]);
  }
}
