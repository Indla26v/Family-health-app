import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/reading_metric.dart';
import '../../data/store.dart';
import 'common.dart';
import 'metric_card.dart';

StatusInfo weightStatus(List<Vital> w) {
  if (w.length < 2) return const StatusInfo(Level.none, 'Steady');
  final d = w.last.a - w[w.length - 2].a;
  if (d.abs() < .5) return const StatusInfo(Level.none, 'Steady');
  return StatusInfo(Level.none, '${d > 0 ? 'Up' : 'Down'} ${d.abs().toStringAsFixed(2)} kg');
}

List<Widget> readingCards(AppStore store, Member member, ValueChanged<ReadingMetric> onTrend) => [
  for (final metric in ReadingMetric.values)
    _readingCard(metric, store.readingsFor(member.id, metric), () => onTrend(metric)),
];

Widget _readingCard(ReadingMetric metric, List<Vital> rows, VoidCallback onTap) {
  final latest = rows.lastOrNull;
  return MetricCard(
    icon: metric.icon,
    label: metric.label,
    empty: latest == null,
    value: latest == null ? '' : metric.format(latest),
    unit: metric.unit,
    status: latest == null ? null : metric == ReadingMetric.weight ? weightStatus(rows) : VitalRanges.ofVital(latest),
    spark: rows.skip(rows.length > 7 ? rows.length - 7 : 0).map((row) => row.a).toList(),
    when: latest == null ? '' : ago(latest.at),
    onTap: onTap,
  );
}

/// Dashed border painter for empty reading slots and dashed action buttons.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashLength = 5.0,
    this.dashGap = 4.0,
    this.radius = 12.0,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = (distance + dashLength < metric.length)
            ? dashLength
            : metric.length - distance;
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.dashGap != dashGap ||
      oldDelegate.radius != radius;
}

/// Title "Latest readings" + status legend dots (Normal, Borderline, High, Steady).
class LatestReadingsHeader extends StatelessWidget {
  const LatestReadingsHeader({super.key});

  Widget _legendDot(Color color, String label, Color textColor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            tr(label),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(
          tr('Latest readings'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: c.text,
            letterSpacing: -0.3,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _legendDot(const Color(0xFF10B981), 'Normal', c.text),
              const SizedBox(width: 8),
              _legendDot(const Color(0xFFF59E0B), 'Borderline', c.text),
              const SizedBox(width: 8),
              _legendDot(const Color(0xFFEF4444), 'High', c.text),
              const SizedBox(width: 8),
              _legendDot(const Color(0xFF64748B), 'Steady', c.text),
            ],
          ),
        ),
      ],
    );
  }
}

/// Individual tile in the 2-column reading grid.
class _ReadingTile extends StatelessWidget {
  const _ReadingTile({
    required this.metric,
    required this.reading,
    required this.onTap,
  });

  final ReadingMetric metric;
  final Vital reading;
  final VoidCallback onTap;

  Color _statusColor(AppPalette c) {
    if (metric == ReadingMetric.weight) {
      return const Color(0xFF64748B); // Steady slate
    }
    final status = VitalRanges.ofVital(reading);
    return switch (status.level) {
      Level.normal => const Color(0xFF10B981),
      Level.borderline => const Color(0xFFF59E0B),
      Level.high || Level.low => const Color(0xFFEF4444),
      Level.none => const Color(0xFF64748B),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dotColor = _statusColor(c);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  if (metric == ReadingMetric.bp) ...[
                    Icon(Icons.monitor_heart_rounded, size: 16, color: c.text),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      tr(metric.label),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      metric.format(reading),
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      metric.unit,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                ago(reading.at),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: c.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed "+ Add reading" tile in the 2-column grid.
class _AddReadingTile extends StatelessWidget {
  const _AddReadingTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CustomPaint(
            painter: DashedBorderPainter(
              color: c.border.withValues(alpha: 0.9),
              strokeWidth: 1.2,
              dashLength: 5,
              dashGap: 4,
              radius: 12,
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: c.textSecondary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr('Add reading'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card for one family member showing avatar, name, and 2-column reading grid.
class MemberLatestReadingsCard extends StatelessWidget {
  const MemberLatestReadingsCard({
    super.key,
    required this.member,
    required this.store,
    required this.onTrend,
    required this.onAdd,
    required this.onHistory,
  });

  final Member member;
  final AppStore store;
  final void Function(ReadingMetric metric) onTrend;
  final VoidCallback onAdd;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final activeReadings = <(ReadingMetric, Vital)>[];
    for (final metric in ReadingMetric.values) {
      final rows = store.readingsFor(member.id, metric);
      if (rows.isNotEmpty) {
        activeReadings.add((metric, rows.last));
      }
    }

    final totalSlots = max(4, ((activeReadings.length + 1) ~/ 2) * 2);
    final rowCount = totalSlots ~/ 2;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: c.border.withValues(alpha: 0.7),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: c.shadow,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Avatar, Name, Chevron
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onHistory,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    MemberAvatar(member, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: c.border.withValues(alpha: 0.6),
          ),
          // 2-column grid
          for (var r = 0; r < rowCount; r++) ...[
            if (r > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: c.border.withValues(alpha: 0.6),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: r * 2 < activeReadings.length
                        ? _ReadingTile(
                            metric: activeReadings[r * 2].$1,
                            reading: activeReadings[r * 2].$2,
                            onTap: () => onTrend(activeReadings[r * 2].$1),
                          )
                        : _AddReadingTile(onTap: onAdd),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: c.border.withValues(alpha: 0.6),
                  ),
                  Expanded(
                    child: r * 2 + 1 < activeReadings.length
                        ? _ReadingTile(
                            metric: activeReadings[r * 2 + 1].$1,
                            reading: activeReadings[r * 2 + 1].$2,
                            onTap: () => onTrend(activeReadings[r * 2 + 1].$1),
                          )
                        : _AddReadingTile(onTap: onAdd),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Latest readings section for the Today screen.
class LatestReadingsSection extends StatelessWidget {
  const LatestReadingsSection({
    super.key,
    required this.people,
    required this.store,
    required this.onTrend,
    required this.onAdd,
    required this.onHistory,
  });

  final List<Member> people;
  final AppStore store;
  final void Function(Member member, ReadingMetric metric) onTrend;
  final void Function(Member member) onAdd;
  final void Function(Member member) onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    if (people.isEmpty) {
      return SurfaceCard(
        child: Text(
          tr('No readings yet. Use Log reading to add one.'),
          style: TextStyle(fontSize: 15, color: c.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LatestReadingsHeader(),
        const SizedBox(height: 10),
        for (var i = 0; i < people.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          MemberLatestReadingsCard(
            member: people[i],
            store: store,
            onTrend: (metric) => onTrend(people[i], metric),
            onAdd: () => onAdd(people[i]),
            onHistory: () => onHistory(people[i]),
          ),
        ],
      ],
    );
  }
}
