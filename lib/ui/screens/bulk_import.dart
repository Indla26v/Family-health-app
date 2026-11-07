import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/bulk.dart';
import '../widgets/common.dart';
import 'review.dart';
import 'today.dart';
import 'upload.dart';

/// "Importing 2019–2025: 142 files · 98 done · 11 need review", per-year rows.
class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});
  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  String? memberId;

  Future<void> _choose() async {
    final s = readStore(context);
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
      if (picked.isEmpty) return;
      final list = <PickedFile>[for (final f in picked) PickedFile(f.name, await f.readAsBytes())];
      BulkImporter.start(s, memberId!, list);
    } catch (_) {
      if (mounted) toast(context, 'Could not open those files');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final job = s.job;
    final people = s.visibleMembers;
    memberId ??= people.first.id;
    final finished = job != null && job.done >= job.total;

    if (job == null || (finished && !job.running)) {
      return PageBody(
        header: const ScreenHeader(title: 'Import old reports', back: true),
        children: [
          if (job != null)
            BannerCard(icon: Icons.check_circle_rounded, tone: 'ok', text: 'Last import finished: ${job.total} files${job.needReview > 0 ? ', ${job.needReview} need review' : ''}.', onTap: job.needReview > 0 ? () => pushPage(context, const ReviewListScreen()) : null),
          const Text('Bring in years of reports at once', style: AppText.titleLarge),
          Text('Choose many PDFs or photos. They are read one by one on this phone. Anything uncertain goes to Needs review.', style: TextStyle(fontSize: 15, color: c.textSecondary, height: 22 / 16)),
          if (people.length > 1) MemberSwitcher(members: people, selectedId: memberId, onSelect: (id) => setState(() => memberId = id!)),
          BigButton(label: 'Choose files', icon: Icons.folder_rounded, onTap: _choose),
        ],
      );
    }

    final years = job.byYear.keys.where((y) => y != 0).toList()..sort();
    final label = years.isEmpty ? '' : (years.length == 1 ? '${years.first} · ' : '${years.first}–${years.last} · ');
    return PageBody(
      header: const ScreenHeader(title: 'Importing old reports', back: true, trailing: SettingsButton()),
      children: [
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label${job.total} files', style: AppText.title),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: job.total == 0 ? 0 : job.done / job.total, minHeight: 12, color: c.accent, backgroundColor: c.border)),
            const SizedBox(height: 8),
            Text('${job.done} of ${job.total} done', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => pushPage(context, const ReviewListScreen()),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.warnTint, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [Icon(Icons.error_rounded, color: c.warn), const SizedBox(width: 10), Expanded(child: Text('${job.needReview} need review', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right_rounded)]),
              ),
            ),
            const SizedBox(height: 12),
            Text('Import continues in the background.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 12),
            if (BulkImporter.hasQueue)
              BigButton(
                secondary: true,
                icon: job.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: job.paused ? 'Resume import' : 'Pause import',
                onTap: () => job.paused ? BulkImporter.resume(s) : BulkImporter.pause(s),
              ),
          ]),
        ),
        const SectionTitle('By year'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            for (final y in job.byYear.keys.toList()..sort()) ...[
              if (y != job.byYear.keys.reduce((a, b) => a < b ? a : b)) const Divider1(),
              Builder(builder: (_) {
                final e = job.byYear[y]!;
                final unknown = y == 0;
                final done = e[1] >= e[0] && !unknown;
                final reading = !unknown && !done && job.running && !job.paused;
                return SizedBox(
                  height: 68,
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(unknown ? 'Waiting to be read' : '$y', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(unknown ? '${e[0]} files left' : '${e[1]} of ${e[0]} files${e[2] > 0 ? ' · ${e[2]} need review' : ''}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                      ]),
                    ),
                    if (unknown || (!done && e[1] == 0)) StatusPill(label: 'Waiting', tone: 'muted') else if (done) StatusPill(label: 'Done', tone: 'ok') else StatusPill(label: reading ? 'Reading' : 'Paused', tone: 'info', icon: reading ? Icons.sync_rounded : Icons.pause_rounded),
                  ]),
                );
              }),
            ],
          ]),
        ),
      ],
    );
  }
}
