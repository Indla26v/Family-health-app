import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/cult_fit.dart';
import '../../data/models.dart';
import '../../data/reading_metric.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/trend_card.dart' show fmtLongDate;
import 'today.dart' show pushPage;
import 'upload.dart';

/// Switches the Health tab between lab/home readings and Cult Fit scans:
/// folder-style tabs where the chosen one is raised, outlined and opens into
/// the page below, and the other sits behind it.
class HealthDataTabs extends StatelessWidget {
  const HealthDataTabs({super.key, required this.cult, required this.onChanged});
  final bool cult;
  final ValueChanged<bool> onChanged;

  static const _tabs = [('Blood data', '🩸'), ('Cult Fit data', '💪')];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final index = cult ? 1 : 0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: LayoutBuilder(
        builder: (context, box) {
          const side = 8.0;
          // Art, gap and label grow with the text size (Large text, Telugu).
          final scaler = MediaQuery.textScalerOf(context);
          final height = max(92.0, scaler.scale(34 * 1.1 * 1.08) + scaler.scale(16 * 1.2) + 26);
          final tabW = min((box.maxWidth - 2 * side) / _tabs.length, 260.0);
          return TweenAnimationBuilder<double>(
            tween: Tween(end: index.toDouble()),
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, at, _) => CustomPaint(
              painter: _FolderTabsPainter(
                count: _tabs.length,
                at: at,
                left: side,
                tabWidth: tabW,
                page: c.bg,
                behind: Color.lerp(c.bg, c.surface, .7)!,
                edge: c.border,
                outline: c.text.withValues(alpha: .78),
              ),
              child: SizedBox(
                height: height,
                child: Row(
                  children: [
                    const SizedBox(width: side),
                    for (var i = 0; i < _tabs.length; i++)
                      SizedBox(
                        width: tabW,
                        child: _FolderTab(label: _tabs[i].$1, art: _tabs[i].$2, selected: i == index, onTap: () => onChanged(i == 1)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FolderTab extends StatelessWidget {
  const _FolderTab({required this.label, required this.art, required this.selected, required this.onTap});
  final String label, art;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : .94,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Opacity(
                  opacity: selected ? 1 : .8,
                  child: Text(art, style: const TextStyle(fontSize: 34, height: 1.1)),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? c.text : c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the tab shapes: every tab as a soft card behind the baseline, then
/// the chosen one at [at] (a tab index, fractional while it slides) filled
/// with the page colour so it opens into the content, with a dark outline
/// whose bottom corners flare out into the baseline.
class _FolderTabsPainter extends CustomPainter {
  _FolderTabsPainter({
    required this.count,
    required this.at,
    required this.left,
    required this.tabWidth,
    required this.page,
    required this.behind,
    required this.edge,
    required this.outline,
  });
  final int count;
  final double at, left, tabWidth;
  final Color page, behind, edge, outline;

  static const _slant = 16.0, _round = 20.0, _flare = 14.0;

  /// The tab outline from bottom-left to bottom-right. With [flare] the bottom
  /// corners curve outwards into the baseline; without it they stop at the base.
  Path _tab(double x0, double h, {required bool flare}) {
    final x1 = x0 + tabWidth;
    double leftAt(double y) => x0 + _slant * (h - y) / h;
    double rightAt(double y) => x1 - _slant * (h - y) / h;
    final p = Path();
    if (flare) {
      p
        ..moveTo(x0 - _flare, h)
        ..quadraticBezierTo(x0, h, leftAt(h - _flare), h - _flare);
    } else {
      p.moveTo(x0, h);
    }
    p
      ..lineTo(leftAt(_round), _round)
      ..quadraticBezierTo(x0 + _slant, 0, x0 + _slant + _round, 0)
      ..lineTo(x1 - _slant - _round, 0)
      ..quadraticBezierTo(x1 - _slant, 0, rightAt(_round), _round);
    if (flare) {
      p
        ..lineTo(rightAt(h - _flare), h - _flare)
        ..quadraticBezierTo(x1, h, x1 + _flare, h);
    } else {
      p.lineTo(x1, h);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final base = h - .75;
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = edge;

    // Tabs behind: soft fill, hairline edge, stepping down a little.
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.translate(0, 4);
      final p = _tab(left + i * tabWidth + 4, base - 4, flare: false);
      canvas.drawPath(Path.from(p)..close(), Paint()..color = behind);
      canvas.drawPath(p, hair);
      canvas.restore();
    }

    // Baseline the content hangs from.
    canvas.drawLine(Offset(0, base), Offset(size.width, base), hair);

    // The chosen tab: page-coloured so it opens into the content below.
    final sel = _tab(left + at * tabWidth, base, flare: true);
    canvas.drawPath(Path.from(sel)..close(), Paint()..color = page);
    canvas.drawRect(Rect.fromLTRB(left + at * tabWidth - _flare, base - .5, left + (at + 1) * tabWidth + _flare, h), Paint()..color = page);
    canvas.drawPath(
      sel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_FolderTabsPainter o) =>
      o.at != at ||
      o.tabWidth != tabWidth ||
      o.left != left ||
      o.page != page ||
      o.behind != behind ||
      o.edge != edge ||
      o.outline != outline ||
      o.count != count;
}

// ───────────────────────────── Dashboard ─────────────────────────────

/// Composition segments: water, fat, protein, minerals. Colours are the
/// validated categorical slots 1–4 (light / dark steps), always shown with a
/// labelled legend so identity never rests on colour alone.
const _segLight = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100)];
const _segDark = [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500)];
const _segments = [('Total body water', 'Water'), ('Fat mass', 'Fat'), ('Protein mass', 'Protein'), ('Others', 'Minerals & other')];

/// Headline tiles under the score card.
const _tiles = ['Weight', 'Fat ratio', 'Muscle mass', 'Visceral fat', 'Lean body mass', 'BMR'];

/// Metrics offered in the trend explorer, in chip order.
const _trendFields = [
  'Weight',
  'Fat ratio',
  'Muscle mass',
  'BMI',
  'Visceral fat',
  'Health score',
  'Skeletal muscle mass',
  'Lean body mass',
  'Fat mass',
  'Subcutaneous fat mass',
  'Total body water',
  'Protein mass',
  'Bone mass',
  'BMR',
  'Body age',
];

double? _v(Vital row, String field) => field == 'Weight' ? row.a : cultMetric(field).of(row.cultFit);

String _when(BuildContext context, DateTime d) => '${fmtLongDate(d)}, ${TimeOfDay.fromDateTime(d).format(context)}';

/// The Health tab's Cult Fit view: the latest scan read at a glance, what
/// changed since the one before, and every number's trend over time.
class CultFitPanel extends StatefulWidget {
  const CultFitPanel({super.key, required this.member});
  final Member member;
  @override
  State<CultFitPanel> createState() => _CultFitPanelState();
}

class _CultFitPanelState extends State<CultFitPanel> {
  String field = 'Weight';
  final _trendsKey = GlobalKey();

  void _import() => pushPage(context, UploadScreen(memberId: widget.member.id, cultOnly: true));

  void _showTrend(String f) {
    setState(() => field = f);
    final target = _trendsKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: .05,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = watchStore(context).readingsFor(widget.member.id, ReadingMetric.weight).where((v) => v.cultFit != null).toList();
    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(kSide, 12, kSide, 108),
        children: [
          EmptyState(
            icon: Icons.fitness_center_rounded,
            message: 'No Cult Fit scans for ${widget.member.name} yet',
            detail: 'In the Cult Fit app, open a Smart Scale measurement and share or download its report PDF, then import it here.',
            buttonLabel: 'Import Cult Fit PDF',
            onButton: _import,
          ),
        ],
      );
    }
    final latest = rows.last;
    final prev = rows.length > 1 ? rows[rows.length - 2] : null;
    final f = latest.cultFit!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(kSide, 10, kSide, 108),
      children: staggered([
        _ScanBar(latest: latest, count: rows.length, onImport: _import),
        const SizedBox(height: 12),
        _ScoreCard(fields: f),
        const SizedBox(height: 12),
        _TileGrid(rows: rows, latest: latest, prev: prev, onTap: _showTrend),
        const SizedBox(height: 12),
        _CompositionCard(latest: latest),
        const SizedBox(height: 12),
        _ColumnsOrStack(
          children: [
            _BmiCard(fields: f),
            _TargetsCard(latest: latest),
          ],
        ),
        const SizedBox(height: 12),
        _ColumnsOrStack(
          children: [
            _BodyTypeCard(fields: f),
            _RatingsCard(fields: f),
          ],
        ),
        const SizedBox(height: 22),
        SectionTitle('Trends', key: _trendsKey),
        const SizedBox(height: 8),
        _TrendExplorer(rows: rows, field: field, color: widget.member.color, onField: (v) => setState(() => field = v)),
        const SizedBox(height: 22),
        const SectionTitle('Scan history'),
        const SizedBox(height: 8),
        _History(rows: rows),
      ]),
    );
  }
}

/// Two cards side by side on wide screens, stacked on phones.
class _ColumnsOrStack extends StatelessWidget {
  const _ColumnsOrStack({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 680) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: children[i])],
          ],
        ),
      );
    },
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.title),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: TextStyle(fontSize: 13, color: c.textSecondary))],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// "Latest scan · 6 Nov 2026, 9:00 AM · 3 scans" with the import action.
class _ScanBar extends StatelessWidget {
  const _ScanBar({required this.latest, required this.count, required this.onImport});
  final Vital latest;
  final int count;
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Latest scan', style: TextStyle(fontSize: 13, color: c.textSecondary)),
              Text(_when(context, latest.at), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Text('$count ${count == 1 ? 'scan' : 'scans'}', style: TextStyle(fontSize: 13, color: c.textSecondary)),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(
          onPressed: onImport,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Import'),
          style: FilledButton.styleFrom(
            backgroundColor: c.accentTint,
            foregroundColor: c.accent,
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

/// The scale's health score as the page's headline, with its verdict and body age.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.fields});
  final Map<String, dynamic> fields;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final score = cultMetric('Health score').of(fields);
    final bodyAge = cultMetric('Body age').of(fields);
    final age = (fields['Age'] as num?)?.toInt();
    final eval = fields['Health evaluation'] as String?;
    final bodyType = fields['Body type'] as String?;
    final small = TextStyle(fontSize: 13, color: c.textSecondary);
    String? ageNote;
    if (bodyAge != null && age != null) {
      final d = bodyAge.round() - age;
      ageNote = d == 0 ? 'Same as your age' : '${d.abs()} ${d.abs() == 1 ? 'year' : 'years'} ${d > 0 ? 'above' : 'below'} your age ($age)';
    }
    return SurfaceCard(
      gradient: c.softGradient,
      padding: const EdgeInsets.all(18),
      semanticLabel:
          'Health score ${score?.toStringAsFixed(1) ?? 'not given'} out of 100${eval == null ? '' : ', $eval'}.'
          '${bodyAge == null ? '' : ' Body age ${bodyAge.round()}.'}${bodyType == null ? '' : ' Body type $bodyType.'}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            _ScoreRing(score: score, color: c.accent, track: c.surface.withValues(alpha: .7)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health score', style: small),
                  const SizedBox(height: 4),
                  if (eval != null) StatusPill(label: eval, tone: cultRatingOk(eval) == false ? 'warn' : 'ok'),
                  const SizedBox(height: 12),
                  if (bodyAge != null) ...[
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Body age ', style: small),
                          TextSpan(
                            text: '${bodyAge.round()}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (ageNote != null) Text(ageNote, style: small),
                  ],
                  if (bodyType != null && bodyType.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Body type ', style: small),
                          TextSpan(
                            text: bodyType,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.color, required this.track});
  final double? score;
  final Color color, track;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox.square(
      dimension: 112,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _RingPainter(fraction: ((score ?? 0) / 100).clamp(0.0, 1.0) * t, color: color, track: track),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score == null ? '–' : score!.toStringAsFixed(score! == score!.roundToDouble() ? 0 : 1),
                  style: TextStyle(fontSize: 34, height: 1, fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 2),
                Text('of 100', style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color, required this.track});
  final double fraction;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, base..color = track);
    if (fraction > 0) canvas.drawArc(rect, -pi / 2, 2 * pi * fraction, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.fraction != fraction || o.color != color || o.track != track;
}

/// KPI row: value, change since the previous scan, and a sparkline once there
/// are two scans. Tap a tile to see its trend.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.rows, required this.latest, required this.prev, required this.onTap});
  final List<Vital> rows;
  final Vital latest;
  final Vital? prev;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) {
    final fields = [
      for (final f in _tiles)
        if (_v(latest, f) != null) f,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final cols = box.maxWidth >= 680 ? 3 : 2;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final f in fields)
              SizedBox(
                width: w,
                child: _Tile(
                  metric: cultMetric(f),
                  value: _v(latest, f)!,
                  before: prev == null ? null : _v(prev!, f),
                  history: [for (final r in rows) ?_v(r, f)],
                  onTap: () => onTap(f),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.metric, required this.value, required this.before, required this.history, required this.onTap});
  final CultMetric metric;
  final double value;
  final double? before;
  final List<double> history;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = before == null ? null : value - before!;
    final good = d == null ? null : metric.improved(d);
    final tone = good == null ? c.textSecondary : (good ? c.ok : c.danger);
    final flat = d != null && double.parse(d.abs().toStringAsFixed(metric.decimals)) == 0;
    final unit = metric.unit == '%' ? '%' : metric.unit;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      semanticLabel:
          '${metric.label} ${metric.withUnit(value)}.'
          '${d == null
              ? ''
              : flat
              ? ' No change since the last scan.'
              : ' ${metric.change(d)} since the last scan${good == null
                    ? ''
                    : good
                    ? ', better'
                    : ', worse'}.'} Show trend.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textSecondary),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    metric.format(value),
                    style: TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w700, color: c.text),
                  ),
                  if (unit.isNotEmpty) ...[const SizedBox(width: 3), Text(unit, style: TextStyle(fontSize: 13, color: c.textSecondary))],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: d == null
                      ? Text('First scan', style: TextStyle(fontSize: 12, color: c.textSecondary))
                      : Row(
                          children: [
                            Icon(
                              flat
                                  ? Icons.remove_rounded
                                  : d > 0
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: tone,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                flat ? 'No change' : metric.change(d),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone),
                              ),
                            ),
                          ],
                        ),
                ),
                if (history.length > 1) Sparkline(history, color: c.accent2, width: 52, height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the body weight is made of, as one segmented bar with a labelled legend.
class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.latest});
  final Vital latest;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final colors = Theme.of(context).brightness == Brightness.dark ? _segDark : _segLight;
    final parts = [
      for (var i = 0; i < _segments.length; i++)
        if (cultMetric(_segments[i].$1).of(latest.cultFit) case final double kg when kg > 0) (name: _segments[i].$2, kg: kg, color: colors[i]),
    ];
    final total = parts.fold<double>(0, (a, p) => a + p.kg);
    if (parts.isEmpty || total <= 0) return const SizedBox.shrink();
    String pct(double kg) => '${(kg / total * 100).round()}%';
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      semanticLabel:
          'Body composition of ${latest.a.toStringAsFixed(1)} kg: ${parts.map((p) => '${p.name} ${p.kg.toStringAsFixed(1)} kg, ${pct(p.kg)}').join('; ')}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle('Body composition', subtitle: 'What ${latest.a.toStringAsFixed(1)} kg is made of'),
            const SizedBox(height: 14),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 16,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: FractionallySizedBox(
                      widthFactor: t.clamp(.001, 1),
                      child: Row(
                        children: [
                          for (var i = 0; i < parts.length; i++) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Expanded(
                              flex: (parts[i].kg * 100).round(),
                              child: ColoredBox(color: parts[i].color, child: const SizedBox.expand()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 520 ? 4 : 2;
                final w = (box.maxWidth - 12.0 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final p in parts)
                      SizedBox(
                        width: w,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: p.color, borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                                  ),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${p.kg.toStringAsFixed(1)} kg',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                                        ),
                                        TextSpan(
                                          text: '  ${pct(p.kg)}',
                                          style: TextStyle(fontSize: 13, color: c.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// BMI against the range the report prints (18.5–25 by default).
class _BmiCard extends StatelessWidget {
  const _BmiCard({required this.fields});
  final Map<String, dynamic> fields;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bmi = cultMetric('BMI').of(fields);
    if (bmi == null) return const SizedBox.shrink();
    final range = RegExp(r'([\d.]+)\s*[–-]\s*([\d.]+)').firstMatch('${fields['BMI reference range'] ?? ''}');
    final lo = double.tryParse(range?.group(1) ?? '') ?? 18.5, hi = double.tryParse(range?.group(2) ?? '') ?? 25.0;
    final status = bmi < lo
        ? const StatusInfo(Level.low, 'Low')
        : bmi > hi
        ? const StatusInfo(Level.high, 'High')
        : const StatusInfo(Level.normal, 'Standard');
    String n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    const min0 = 14.0, max0 = 36.0;
    final minV = min(min0, bmi - 1), maxV = max(max0, bmi + 1);
    double at(double v) => ((v - minV) / (maxV - minV)).clamp(0.0, 1.0);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      semanticLabel: 'BMI ${bmi.toStringAsFixed(1)}, ${status.word}. Standard range ${n(lo)} to ${n(hi)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle('Body mass index', subtitle: 'Standard ${n(lo)}–${n(hi)} kg/m²', trailing: StatusPill.info(status)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: bmi.toStringAsFixed(1),
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.text),
                  ),
                  TextSpan(
                    text: '  kg/m²',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final zones = [(0.0, at(lo), c.warn), (at(lo), at(hi), c.ok), (at(hi), 1.0, c.danger)];
                return SizedBox(
                  height: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 6,
                        left: 0,
                        right: 0,
                        height: 8,
                        child: Row(
                          children: [
                            for (var i = 0; i < zones.length; i++) ...[
                              if (i > 0) const SizedBox(width: 2),
                              Expanded(
                                flex: max(1, ((zones[i].$2 - zones[i].$1) * 1000).round()),
                                child: Container(
                                  decoration: BoxDecoration(color: zones[i].$3.withValues(alpha: .35), borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        left: (at(bmi) * w - 10).clamp(0.0, w - 20),
                        top: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: c.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.text, width: 3),
                          ),
                        ),
                      ),
                      for (final (v, align) in [(lo, at(lo)), (hi, at(hi))])
                        Positioned(
                          top: 22,
                          left: (align * w - 20).clamp(0.0, w - 40),
                          width: 40,
                          child: Text(
                            n(v),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: c.textSecondary),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            Row(
              children: [
                Text('Low', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                const Spacer(),
                Text('Standard', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                const Spacer(),
                Text('High', style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The scale's own targets: standard weight and how far weight, fat and muscle are from it.
class _TargetsCard extends StatelessWidget {
  const _TargetsCard({required this.latest});
  final Vital latest;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = latest.cultFit;
    final standard = cultMetric('Standard weight').of(f);
    final rows = [
      for (final (field, label) in [('Weight control', 'Weight'), ('Fat control', 'Fat'), ('Muscle control', 'Muscle')])
        if (cultMetric(field).of(f) case final double v) (label: label, v: v),
    ];
    if (standard == null && rows.isEmpty) return const SizedBox.shrink();
    final now = latest.a;
    final hi = max(now, standard ?? now);
    String kg(double v) => '${v.toStringAsFixed(1)} kg';
    String change(double v) => v.abs() < .05 ? 'Keep as is' : '${v > 0 ? 'Gain' : 'Lose'} ${v.abs().toStringAsFixed(1)} kg';
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      semanticLabel:
          'Scale targets. ${standard == null ? '' : 'Standard weight ${kg(standard)}, now ${kg(now)}. '}${rows.map((r) => '${r.label}: ${change(r.v)}').join('. ')}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Scale targets', subtitle: 'Suggested by the Cult Smart Scale'),
            if (standard != null) ...[
              const SizedBox(height: 14),
              for (final (label, v, color) in [('Now', now, c.accent2), ('Standard', standard, c.ok)]) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: max(4.0, box.maxWidth * v / hi),
                            height: 8,
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 64,
                      child: Text(
                        kg(v),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Divider1(),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r.label, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                      ),
                      Text(
                        change(r.v),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The report's 3 × 3 body-type grid with the scan's type highlighted.
class _BodyTypeCard extends StatelessWidget {
  const _BodyTypeCard({required this.fields});
  final Map<String, dynamic> fields;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final type = (fields['Body type'] as String?)?.trim() ?? '';
    if (type.isEmpty) return const SizedBox.shrink();
    final axis = TextStyle(fontSize: 11, color: c.textSecondary);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      semanticLabel: 'Body type: $type.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle('Body type', subtitle: type),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reads top to bottom: body fat rises down the grid.
                RotatedBox(
                  quarterTurns: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Body fat', style: axis),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_rounded, size: 12, color: axis.color),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      for (final row in cultBodyTypes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              for (var i = 0; i < row.length; i++) ...[
                                if (i > 0) const SizedBox(width: 4),
                                Expanded(
                                  child: _TypeCell(label: row[i], selected: row[i].toLowerCase() == type.toLowerCase()),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Muscle mass', style: axis),
                            const SizedBox(width: 2),
                            Icon(Icons.arrow_forward_rounded, size: 12, color: axis.color),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCell extends StatelessWidget {
  const _TypeCell({required this.label, required this.selected});
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: selected ? c.accent : c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.2, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? c.onAccent : c.textSecondary),
        ),
      ),
    );
  }
}

/// Bone and muscle with the report's rating words.
class _RatingsCard extends StatelessWidget {
  const _RatingsCard({required this.fields});
  final Map<String, dynamic> fields;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = [
      for (final f in ['Muscle mass', 'Skeletal muscle mass', 'Bone mass', 'Lean body mass', 'Subcutaneous fat mass'])
        if (cultMetric(f).of(fields) case final double v) (m: cultMetric(f), v: v, rating: fields['$f rating'] as String?),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Muscle, bone & fat', subtitle: 'Ratings from the report'),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider1(),
            Semantics(
              label: '${rows[i].m.label} ${rows[i].m.withUnit(rows[i].v)}${rows[i].rating == null ? '' : ', ${rows[i].rating}'}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(rows[i].m.label, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                    ),
                    Text(
                      rows[i].m.withUnit(rows[i].v),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    if (rows[i].rating != null) ...[
                      const SizedBox(width: 10),
                      StatusPill(
                        label: rows[i].rating!,
                        tone: switch (cultRatingOk(rows[i].rating)) {
                          true => 'ok',
                          false => 'warn',
                          null => 'muted',
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One metric over time: a chip row picks it, the chart and summary follow.
class _TrendExplorer extends StatelessWidget {
  const _TrendExplorer({required this.rows, required this.field, required this.color, required this.onField});
  final List<Vital> rows;
  final String field;
  final Color color;
  final ValueChanged<String> onField;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fields = [
      for (final f in _trendFields)
        if (rows.any((r) => _v(r, f) != null)) f,
    ];
    final current = fields.contains(field) ? field : fields.first;
    final m = cultMetric(current);
    final pts = [
      for (final r in rows)
        if (_v(r, current) case final double v) ChartPoint(r.at, v, label: m.format(v), lab: 'Cult Smart Scale'),
    ];
    final values = [for (final p in pts) p.value];
    final first = pts.first, last = pts.last;
    final stat = TextStyle(fontSize: 12, color: c.textSecondary);
    Widget cell(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: stat),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
    final d = last.value - first.value;
    final good = m.improved(d);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: fields.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final f = fields[i];
                final on = f == current;
                return Semantics(
                  button: true,
                  selected: on,
                  child: Material(
                    color: on ? c.accent : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onField(f),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            cultMetric(f).label,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onAccent : c.textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrendChart(
                  key: ValueKey(current),
                  series: [ChartSeries(pts, color, name: m.label)],
                  unit: m.unit,
                  decimals: m.decimals,
                  height: 200,
                  initial: Period.all,
                  periods: const [Period.m3, Period.m6, Period.y1, Period.all],
                  periodLabelOf: (p) => switch (p) {
                    Period.m3 => '3M',
                    Period.m6 => '6M',
                    Period.y1 => '1Y',
                    Period.all => 'All',
                  },
                  cutoffOf: (p) {
                    final n = DateTime.now();
                    return switch (p) {
                      Period.m3 => DateTime(n.year, n.month - 3, n.day),
                      Period.m6 => DateTime(n.year, n.month - 6, n.day),
                      Period.y1 => DateTime(n.year - 1, n.month, n.day),
                      Period.all => null,
                    };
                  },
                  summary:
                      '${m.label} from ${pts.length} ${pts.length == 1 ? 'scan' : 'scans'}. Latest ${m.withUnit(last.value)} on ${fmtLongDate(last.date)}.',
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    cell('Latest', m.withUnit(last.value)),
                    cell('Lowest', m.withUnit(values.reduce(min))),
                    cell('Highest', m.withUnit(values.reduce(max))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pts.length > 1 ? 'Since first' : 'Change', style: stat),
                          const SizedBox(height: 2),
                          Text(
                            pts.length > 1 ? m.change(d) : '–',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: good == null
                                  ? c.text
                                  : good
                                  ? c.ok
                                  : c.danger,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every scan, newest first; tap one for its full report.
class _History extends StatelessWidget {
  const _History({required this.rows});
  final List<Vital> rows;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final list = rows.reversed.toList();
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Divider1()),
              InkWell(
                onTap: () => pushPage(context, CultScanScreen(vitalId: list[i].id)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fmtLongDate(list[i].at), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            Text(
                              [
                                TimeOfDay.fromDateTime(list[i].at).format(context),
                                if (cultMetric('Fat ratio').of(list[i].cultFit) case final double fat) 'Body fat ${fat.toStringAsFixed(1)}%',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: c.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${list[i].a.toStringAsFixed(1)} kg',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── One scan ─────────────────────────────

/// Sections of the full report, in the order the PDF prints them.
const _sections = <(String, List<String>)>[
  ('Overview', ['Health score', 'Health evaluation', 'Body type', 'Body age', 'BMI']),
  ('Body composition', ['Weight', 'Total body water', 'Protein mass', 'Fat mass', 'Others']),
  ('Weight management', ['Standard weight', 'Weight control', 'Fat control', 'Muscle control', 'BMR']),
  ('Fat analysis', ['Fat ratio', 'Visceral fat', 'Subcutaneous fat mass']),
  ('Bone & muscle', ['Muscle mass', 'Skeletal muscle mass', 'Bone mass', 'Lean body mass']),
  ('Profile on the scale', ['Scale profile', 'Gender', 'Age', 'Height']),
];

/// Shown elsewhere on the row (a rating pill, the BMI range) or a copy of another field.
bool _hidden(String key) => key.endsWith(' rating') || key == 'BMI reference range' || key == 'Chart weight';

/// Every number from one Cult Fit report, grouped like the PDF, with a delete action.
class CultScanScreen extends StatelessWidget {
  const CultScanScreen({super.key, required this.vitalId});
  final String vitalId;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final row = s.vitals.where((v) => v.id == vitalId).firstOrNull;
    final member = row == null ? null : s.member(row.memberId);
    if (row == null || row.cultFit == null || member == null) return const UnavailableMemberPage(title: 'Cult Fit scan');
    final c = context.c;
    final f = row.cultFit!;
    final shown = {for (final (_, keys) in _sections) ...keys};
    final rest = [
      for (final k in f.keys)
        if (!shown.contains(k) && !_hidden(k)) k,
    ];
    String value(String key) {
      final v = key == 'Weight' ? row.a : f[key];
      if (v is num) {
        if (key == 'Age') return '${v.round()} years';
        if (key == 'Height') return '${v.toStringAsFixed(1)} cm';
        return cultMetric(key).withUnit(v.toDouble());
      }
      return '$v';
    }

    Widget section(String title, List<String> keys) {
      final present = [
        for (final k in keys)
          if (k == 'Weight' || f[k] != null) k,
      ];
      if (present.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 8),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < present.length; i++) ...[
                  if (i > 0) Divider1(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cultMetric(present[i]).label == present[i] ? present[i] : cultMetric(present[i]).label,
                            style: TextStyle(fontSize: 15, color: c.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          value(present[i]),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                        if (f['${present[i]} rating'] case final String rating) ...[
                          const SizedBox(width: 10),
                          StatusPill(
                            label: rating,
                            tone: switch (cultRatingOk(rating)) {
                              true => 'ok',
                              false => 'warn',
                              null => 'muted',
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return PageBody(
      header: ScreenHeader(
        title: fmtLongDate(row.at),
        subtitle: '${member.name} · ${TimeOfDay.fromDateTime(row.at).format(context)} · Cult Smart Scale',
        back: true,
      ),
      bottom: BigButton(
        label: 'Delete this scan',
        icon: Icons.delete_outline_rounded,
        secondary: true,
        danger: true,
        onTap: () async {
          final yes = await confirmDialog(
            context,
            'Delete this scan?',
            'The Cult Fit scan from ${_when(context, row.at)} and its weight reading will be removed for ${member.name}.',
          );
          if (!yes || !context.mounted) return;
          s.deleteVital(row.id);
          Navigator.of(context).maybePop();
          toast(context, 'Scan deleted', ok: true);
        },
      ),
      children: [for (final (title, keys) in _sections) section(title, keys), if (rest.isNotEmpty) section('Other', rest)],
    );
  }
}
