import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'log_reading.dart';
import 'today.dart';

class ReadingHistoryScreen extends StatefulWidget {
  const ReadingHistoryScreen({
    super.key,
    this.memberId,
    this.type,
    this.afterMeal,
  });
  final String? memberId;
  final VitalType? type;
  final bool? afterMeal;

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  String? memberId;
  late VitalType? type = widget.type;
  late bool? afterMeal = widget.afterMeal;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??=
        s.member(widget.memberId)?.id ??
        s.member(s.selectedId)?.id ??
        people.first.id;
    final m = s.member(memberId)!;
    final rows =
        s.vitals
            .where(
              (v) =>
                  v.memberId == m.id &&
                  (type == null || v.type == type) &&
                  (type != VitalType.sugar ||
                      afterMeal == null ||
                      v.afterMeal == afterMeal),
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Reading history',
              subtitle: m.name,
              back: true,
              trailing: IconButton(
                tooltip: 'Log reading',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => pushPage(
                  context,
                  LogReadingScreen(
                    memberId: m.id,
                    mode: type ?? VitalType.bp,
                    afterMeal: afterMeal ?? false,
                  ),
                ),
              ),
            ),
            if (people.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSide),
                child: MemberPicker(
                  members: people,
                  selectedId: m.id,
                  onSelect: (id) => setState(() => memberId = id),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(kSide),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ChoiceChips<VitalType?>(
                      options: const [
                        (null, 'All'),
                        (VitalType.bp, 'BP'),
                        (VitalType.sugar, 'Sugar'),
                        (VitalType.weight, 'Weight'),
                        (VitalType.spo2, 'SpO2'),
                      ],
                      value: type,
                      onChanged: (v) => setState(() {
                        type = v;
                        afterMeal = null;
                      }),
                    ),
                  ),
                  if (type == VitalType.sugar) ...[
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ChoiceChips<bool?>(
                        options: const [
                          (null, 'All sugar'),
                          (false, 'Fasting'),
                          (true, 'After meal'),
                        ],
                        value: afterMeal,
                        onChanged: (v) => setState(() => afterMeal = v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    '${rows.length} ${rows.length == 1 ? 'reading' : 'readings'} · newest first',
                    style: TextStyle(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.history_rounded,
                        message: 'No readings yet',
                        detail: 'Saved readings will appear here.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(kSide, 0, kSide, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final v = rows[i];
                        final (title, value, unit) = switch (v.type) {
                          VitalType.bp => (
                            'Blood pressure',
                            '${v.a.round()}/${v.b.round()}',
                            'mmHg',
                          ),
                          VitalType.sugar => (
                            v.afterMeal
                                ? 'Post-meal glucose'
                                : 'Fasting glucose',
                            '${v.a.round()}',
                            'mg/dL',
                          ),
                          VitalType.weight => (
                            'Weight',
                            v.a.toStringAsFixed(2),
                            'kg',
                          ),
                          VitalType.spo2 => (
                            'Oxygen (SpO2)',
                            '${v.a.round()}',
                            '%',
                          ),
                        };
                        return SurfaceCard(
                          key: ValueKey(v.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete reading',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    onPressed: () async {
                                      final confirmed = await confirmDialog(
                                        context,
                                        'Delete reading?',
                                        '$title: $value $unit on ${fmtDate(v.at)}, ${fmtTime(v.at)}.',
                                      );
                                      if (confirmed && context.mounted) {
                                        s.deleteVital(v.id);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '$value $unit',
                                    style: AppText.numberLarge,
                                  ),
                                  if (v.type != VitalType.weight)
                                    StatusPill.info(VitalRanges.ofVital(v)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${fmtDate(v.at)} · ${fmtTime(v.at)}${v.type == VitalType.bp && v.pulse > 0 ? ' · Pulse ${v.pulse.round()} bpm' : ''}',
                                style: TextStyle(color: c.textSecondary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
