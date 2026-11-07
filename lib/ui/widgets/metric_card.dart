import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import 'charts.dart';
import 'common.dart';

/// Label, big number + unit, status pill, 7-point sparkline, "2 days ago".
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.status,
    this.spark = const [],
    this.when = '',
    this.onTap,
    this.width = 156,
    this.empty = false,
  });
  final IconData icon;
  final String label, value, unit, when;
  final StatusInfo? status;
  final List<double> spark;
  final VoidCallback? onTap;
  final double width;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: width,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        semanticLabel: empty ? '${tr(label)}: no reading yet' : '${tr(label)}: $value $unit${status == null ? '' : ', ${tr(status!.word)}'}. $when',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: c.accent),
            const SizedBox(width: 6),
            Expanded(child: Text(tr(label), maxLines: 2, style: TextStyle(fontSize: 14, height: 18 / 14, fontWeight: FontWeight.w600, color: c.textSecondary))),
          ]),
          const SizedBox(height: 8),
          if (empty)
            Text('No reading yet', style: TextStyle(fontSize: 16, height: 26 / 18, color: c.textSecondary))
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: value, style: AppText.numberLarge),
                TextSpan(text: ' $unit', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              ])),
            ),
          const SizedBox(height: 4),
          if (spark.length > 1) Sparkline(spark, width: width - 28, height: 30),
          const SizedBox(height: 8),
          if (status != null) StatusPill.info(status!),
          if (when.isNotEmpty) ...[const SizedBox(height: 6), Text(when, style: TextStyle(fontSize: 14, color: c.textSecondary))],
        ]),
      ),
    );
  }
}

/// Circular progress used for "3/6 doses".
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.fraction, required this.label, this.size = 64});
  final double fraction;
  final String label;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: '$label doses taken today',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size(size, size), painter: _Ring(fraction.clamp(0, 1), c.accent, c.border)),
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.f, this.fg, this.bg);
  final double f;
  final Color fg, bg;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(5, 5, s.width - 10, s.height - 10);
    canvas.drawArc(r, 0, 6.2832, false, Paint()..color = bg..style = PaintingStyle.stroke..strokeWidth = 7);
    canvas.drawArc(r, -1.5708, 6.2832 * f, false, Paint()..color = fg..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_Ring o) => o.f != f || o.fg != fg;
}
