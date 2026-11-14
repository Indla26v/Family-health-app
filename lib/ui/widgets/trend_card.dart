import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import 'common.dart';

const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// One result on a trend: when, the value to plot, how to show it, whether it is
/// out of range, and the report it came from (if any).
class TrendPoint {
  const TrendPoint({required this.date, required this.value, required this.label, this.outside = false, this.docId});
  final DateTime date;
  final double value;
  final String label;
  final bool outside;
  final String? docId;
}

/// A test (or reading) as a full-width card, kept quiet so the numbers read first:
/// title and status, the latest value and its date, a simple chart over the normal
/// range (from two results on), then the range and the previous value. Tap it for the full history.
class TrendCard extends StatelessWidget {
  const TrendCard({
    super.key,
    required this.title,
    required this.unit,
    required this.points,
    required this.status,
    this.icon,
    this.low,
    this.high,
    this.onTap,
    this.valueText,
    this.source,
  });

  final String title, unit;
  final IconData? icon;

  /// Oldest first.
  final List<TrendPoint> points;
  final StatusInfo status;
  final double? low, high;
  final VoidCallback? onTap;

  /// Overrides the latest value text (e.g. "138/86" for blood pressure).
  final String? valueText;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final last = points.last;
    final prev = points.length > 1 ? points[points.length - 2] : null;
    final tone = switch (status.level) { Level.normal => c.ok, Level.borderline => c.warn, Level.none => c.textSecondary, _ => c.danger };
    final range = low != null && high != null ? '${_n(low!)}–${_n(high!)}' : high != null ? 'below ${_n(high!)}' : low != null ? 'above ${_n(low!)}' : null;
    final small = TextStyle(fontSize: 13, color: c.textSecondary);
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      semanticLabel: '$title ${valueText ?? last.label} $unit, ${status.word}, ${fmtLongDate(last.date)}. ${source ?? ''}'
          '${range == null ? '' : ' Normal $range $unit.'}${prev == null ? '' : ' Previous ${prev.label}.'} ${points.length} results.',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: c.textSecondary), const SizedBox(width: 8)],
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            StatusPill.info(status),
          ]),
          if (source != null) ...[
            const SizedBox(height: 4),
            Text(source!, style: small),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(valueText ?? last.label, style: TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w700, color: tone == c.ok ? c.text : tone, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 4),
              Text(unit, style: small),
            ]))),
            const SizedBox(width: 8),
            Text(fmtLongDate(last.date), style: small),
          ]),
          // One result has no trend yet: the value and its range say it all.
          if (points.length > 1) ...[
            const SizedBox(height: 12),
            SmoothTrend(points: points, low: low, high: high, color: c.accent2, height: 96),
          ],
          if (range != null || prev != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (range != null) ...[
                Container(width: 10, height: 10, decoration: BoxDecoration(color: c.ok.withValues(alpha: .25), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Expanded(child: Text('Normal $range $unit', maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
              ] else
                const Spacer(),
              if (prev != null)
                Text.rich(TextSpan(style: small, children: [
                  const TextSpan(text: 'Previous  '),
                  TextSpan(text: prev.label, style: TextStyle(fontWeight: FontWeight.w700, color: prev.outside ? c.danger : c.text, fontFeatures: const [FontFeature.tabularFigures()])),
                ])),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Date for a card's latest result: "25 Oct 2026".
String fmtLongDate(DateTime d) => '${d.day} ${_mo[d.month - 1]} ${d.year}';

/// A range limit without trailing zeros: 100.00 → "100", 5.70 → "5.7".
String _n(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// Quiet chart: the normal range as a soft band, one smooth line with a light fill,
/// the latest result marked, and the first/last dates. Every result gets a small dot
/// (red when out of range) only while there are few enough to read.
class SmoothTrend extends StatelessWidget {
  const SmoothTrend({super.key, required this.points, required this.color, this.low, this.high, this.height = 110});
  final List<TrendPoint> points;
  final Color color;
  final double? low, high;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SmoothPainter(points: points, color: color, low: low, high: high, band: c.ok, danger: c.danger, surface: c.surface, text: c.textSecondary)),
      ),
    );
  }
}

/// Up to this many results each get a dot; beyond that only the latest does.
const _maxDots = 12;

class _SmoothPainter extends CustomPainter {
  _SmoothPainter({required this.points, required this.color, required this.low, required this.high, required this.band, required this.danger, required this.surface, required this.text});
  final List<TrendPoint> points;
  final Color color, band, danger, surface, text;
  final double? low, high;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const labelH = 18.0, padX = 6.0, padTop = 8.0;
    final chartH = size.height - labelH;

    // Y range covers the values and the normal range, with some air.
    final ys = [for (final p in points) p.value, ?low, ?high];
    var lo = ys.reduce(min), hi = ys.reduce(max);
    if (hi - lo < 1e-9) {
      final pad = hi.abs() * .2 + 1;
      lo -= pad;
      hi += pad;
    }
    final airY = (hi - lo) * .12;
    lo -= airY;
    hi += airY;
    double y(double v) => padTop + (chartH - padTop - 6) * (1 - (v - lo) / (hi - lo));

    // X by date; a single result sits in the middle.
    final t0 = points.first.date.millisecondsSinceEpoch.toDouble(), t1 = points.last.date.millisecondsSinceEpoch.toDouble();
    double x(TrendPoint p) => points.length == 1 || t1 == t0 ? size.width / 2 : padX + (size.width - 2 * padX) * (p.date.millisecondsSinceEpoch - t0) / (t1 - t0);

    // Normal range: a soft band only (its numbers are written under the chart).
    if (low != null || high != null) {
      final top = y(high ?? hi).clamp(0.0, chartH), bottom = y(low ?? lo).clamp(0.0, chartH);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(0, top, size.width, bottom), const Radius.circular(8)), Paint()..color = band.withValues(alpha: .12));
    }

    final pts = [for (final p in points) Offset(x(p), y(p.value))];

    if (pts.length > 1) {
      // Smooth curve: horizontal tangents at each point, so it never overshoots.
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        final mx = (a.dx + b.dx) / 2;
        line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      final fill = Path.from(line)
        ..lineTo(pts.last.dx, chartH)
        ..lineTo(pts.first.dx, chartH)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .14), color.withValues(alpha: 0)]).createShader(Rect.fromLTWH(0, 0, size.width, chartH)),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Small dots while there are few results; the latest always, a little bigger.
    final dots = points.length <= _maxDots;
    for (var i = 0; i < pts.length; i++) {
      final latest = i == pts.length - 1;
      if (!dots && !latest) continue;
      final col = points[i].outside ? danger : color;
      canvas.drawCircle(pts[i], latest ? 5 : 3.5, Paint()..color = surface);
      canvas.drawCircle(pts[i], latest ? 3.5 : 2.2, Paint()..color = col);
    }

    // Dates: first and last ("Aug 2020", or "4 Nov" when they are close together).
    final close = points.last.date.difference(points.first.date).inDays < 60;
    String when(DateTime d) => close ? '${d.day} ${_mo[d.month - 1]}' : '${_mo[d.month - 1]} ${d.year}';
    void label(String s, double cx, {bool alignRight = false, bool center = false}) {
      final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 11, color: text)), textDirection: TextDirection.ltr)..layout();
      final dx = center ? cx - tp.width / 2 : (alignRight ? cx - tp.width : cx);
      tp.paint(canvas, Offset(dx.clamp(0, size.width - tp.width), size.height - tp.height));
    }

    if (points.length == 1) {
      label(when(points.first.date), size.width / 2, center: true);
    } else {
      label(when(points.first.date), 0);
      label(when(points.last.date), size.width, alignRight: true);
    }
  }

  @override
  bool shouldRepaint(_SmoothPainter old) => old.points != points || old.color != color || old.low != low || old.high != high || old.band != band;
}
