import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/reading_metric.dart';
import '../../data/store.dart';
import 'common.dart';
import 'metric_card.dart';
import 'motion.dart';

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

  Color _statusColor() {
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
    final dotColor = _statusColor();

    return Material(
      color: c.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
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
                      maxLines: 2,
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

/// One open member with direct links to readings, history and entry.
class LatestReadingsSection extends StatefulWidget {
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
  State<LatestReadingsSection> createState() => LatestReadingsSectionState();
}

class LatestReadingsSectionState extends State<LatestReadingsSection>
    with SingleTickerProviderStateMixin {
  final _headers = <String, GlobalKey>{};
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 230),
    value: 1,
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed && _closing != null) {
      setState(() => _closing = null);
    }
  });
  String? _selected;
  String? _closing;
  Timer? _settleTimer;
  double? _dragStart;

  String? get _open => widget.people.any((m) => m.id == _selected)
      ? _selected : widget.people.firstOrNull?.id;

  @override
  void didUpdateWidget(LatestReadingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.people.map((member) => member.id).toSet();
    _headers.removeWhere((id, _) => !ids.contains(id));
    if (_selected != null && !ids.contains(_selected)) {
      _selected = null;
      _closing = null;
      _settleTimer?.cancel();
      _dragStart = null;
      _animation.stop();
      _animation.value = 1;
    }
  }

  void handleScroll(ScrollNotification notification) {
    if (notification.depth != 0) return;
    if (notification is ScrollStartNotification) {
      _settleTimer?.cancel();
      _dragStart = notification.dragDetails == null ? null : notification.metrics.pixels;
    } else if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      _dragStart ??= notification.metrics.pixels - (notification.scrollDelta ?? 0);
    } else if (notification is ScrollEndNotification) {
      final start = _dragStart;
      _dragStart = null;
      if (start != null && (notification.metrics.pixels - start).abs() >= 12) {
        _settleTimer = Timer(const Duration(milliseconds: 160), _openFocusedMember);
      }
    }
  }

  void _openFocusedMember() {
    if (!mounted || widget.people.length < 2 || _animation.isAnimating) return;
    final position = Scrollable.maybeOf(context)?.position;
    final section = context.findRenderObject();
    if (position == null || !position.hasContentDimensions ||
        section is! RenderBox || !section.attached || !section.hasSize) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(section);
    if (viewport == null || position.extentAfter <= 1) return;
    final middle = position.viewportDimension / 2;
    double topOf(RenderBox box) =>
        viewport.getOffsetToReveal(box, 0).offset - position.pixels;
    if (topOf(section) + section.size.height <= middle + 24) return;

    String? closest;
    var distance = (position.viewportDimension * .09).clamp(32.0, 60.0);
    for (final member in widget.people) {
      final header = _headers[member.id]?.currentContext?.findRenderObject();
      if (header is! RenderBox || !header.attached || !header.hasSize) continue;
      final gap = (topOf(header) + header.size.height / 2 - middle).abs();
      if (gap < distance) {
        closest = member.id;
        distance = gap;
      }
    }
    if (closest != null) _select(closest);
  }

  void _select(String id) {
    _settleTimer?.cancel();
    final previous = _open;
    if (id == previous) return;
    final animate = !reduceMotion(context);
    _animation.stop();
    setState(() {
      _selected = id;
      _closing = animate ? previous : null;
    });
    if (animate) {
      _animation.forward(from: 0);
    } else {
      _animation.value = 1;
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  Widget _body(Member member) {
    final available = [
      for (final metric in ReadingMetric.values)
        if (widget.store.readingsFor(member.id, metric).lastOrNull case final reading?)
          _ReadingTile(metric: metric, reading: reading, onTap: () => widget.onTrend(member, metric)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No readings yet', style: TextStyle(color: context.c.textSecondary)),
          ),
        for (var index = 0; index < available.length; index += 2) ...[
          if (index > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: available[index]),
              const SizedBox(width: 8),
              Expanded(child: index + 1 < available.length ? available[index + 1] : const SizedBox()),
            ]),
          ),
        ],
        Wrap(spacing: 8, children: [
          TextButton(onPressed: () => widget.onHistory(member), child: const Text('Reading history')),
          TextButton.icon(onPressed: () => widget.onAdd(member), icon: const Icon(Icons.add_rounded, size: 17), label: const Text('Add reading')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (widget.people.isEmpty) {
      return const SurfaceCard(child: Text('No readings yet. Use Log reading to add one.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const LatestReadingsHeader(),
      const SizedBox(height: 8),
      for (final (index, member) in widget.people.indexed) ...[
        if (index > 0) const SizedBox(height: 8),
        SurfaceCard(
          key: ValueKey(member.id),
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              key: _headers.putIfAbsent(member.id, GlobalKey.new),
              button: true,
              expanded: member.id == _open,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _select(member.id),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      MemberAvatar(member, size: 32),
                      const SizedBox(width: 8),
                      Expanded(child: Text(member.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      AnimatedRotation(
                        turns: member.id == _open ? .5 : 0,
                        duration: reduceMotion(context) ? Duration.zero : _animation.duration!,
                        curve: kEaseOut,
                        child: Icon(Icons.expand_more_rounded, color: c.textSecondary),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            if (member.id == _open || member.id == _closing)
              ExcludeSemantics(
                excluding: member.id != _open,
                child: IgnorePointer(
                  ignoring: member.id != _open,
                  child: AnimatedBuilder(
                    animation: _animation,
                    child: _body(member),
                    builder: (_, child) {
                      final progress = Curves.easeInOutCubic.transform(_animation.value);
                      final factor = member.id == _open ? progress : 1 - progress;
                      return ClipRect(
                        child: Align(alignment: Alignment.topCenter, heightFactor: factor, child: child),
                      );
                    },
                  ),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }
}
