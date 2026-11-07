import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'bulk_import.dart';
import 'doc_viewer.dart';
import 'parse_failed.dart';
import 'review.dart';
import 'today.dart';
import 'upload.dart';

/// Open the right screen for a document, depending on its state.
void openDocFlow(BuildContext context, Doc d) {
  switch (d.status) {
    case DocStatus.needsReview:
      pushPage(context, ReviewScreen(docId: d.id));
    case DocStatus.failed:
      pushPage(context, ParseFailedScreen(docId: d.id));
    case DocStatus.parsed:
      openDocument(context, d.id);
    case DocStatus.processing:
      pushPage(context, const UploadScreen());
  }
}

class DocRow extends StatelessWidget {
  const DocRow({super.key, required this.doc, this.showMember = true});
  final Doc doc;
  final bool showMember;
  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final m = s.member(doc.memberId);
    final (label, tone, icon) = switch (doc.status) {
      DocStatus.parsed => ('Parsed', 'ok', null),
      DocStatus.needsReview => ('Needs review', 'warn', null),
      DocStatus.failed => ('Failed', 'danger', null),
      DocStatus.processing => ('Reading…', 'info', Icons.sync_rounded),
    };
    final count = doc.kind == DocKind.prescription ? (doc.testCount == 0 ? 'Prescription' : '${doc.testCount} items') : (doc.status == DocStatus.failed && doc.testCount == 0 ? '—' : '${doc.testCount} tests');
    return InkWell(
      onTap: () => openDocFlow(context, doc),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            IconBadge(doc.isImage || doc.kind == DocKind.prescription ? Icons.photo_camera_rounded : Icons.description_rounded, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doc.lab, style: const TextStyle(fontSize: 15, height: 22 / 17, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  if (showMember && m != null) ...[MemberAvatar(m, size: 24), const SizedBox(width: 6)],
                  Flexible(child: Text('${fmtDate(doc.date)} · $count', style: TextStyle(fontSize: 14, color: c.textSecondary), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                StatusPill(label: label, tone: tone, icon: icon),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          ]),
        ),
      ),
    );
  }
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final search = TextEditingController();
  String? member;
  int? year;
  DocKind? type;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool _matches(AppStore s, Doc d) {
    if (member != null && d.memberId != member) return false;
    if (year != null && d.date.year != year) return false;
    if (type != null && d.kind != type) return false;
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final m = s.member(d.memberId)?.name.toLowerCase() ?? '';
    final tests = s.labsOfDoc(d.id).map((l) => testByKey(l.testKey)?.name.toLowerCase() ?? '').join(' ');
    return d.lab.toLowerCase().contains(q) || m.contains(q) || fmtDate(d.date).toLowerCase().contains(q) || tests.contains(q) || '${d.date.year}'.contains(q);
  }

  Widget _filter<T>(BuildContext context, String label, T? value, List<(T?, String)> options, ValueChanged<T?> onPick) {
    final c = context.c;
    final active = value != null;
    final shown = active ? options.firstWhere((o) => o.$1 == value).$2 : label;
    return PopupMenuButton<int>(
      tooltip: 'Filter by $label',
      offset: const Offset(0, 48),
      onSelected: (i) => onPick(options[i].$1),
      itemBuilder: (_) => [for (var i = 0; i < options.length; i++) PopupMenuItem(value: i, child: Text(options[i].$2, style: const TextStyle(fontSize: 15)))],
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(color: active ? c.accentTint : c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? c.accent : c.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(shown, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: active ? c.accent : c.textSecondary)),
          Icon(Icons.expand_more_rounded, size: 22, color: active ? c.accent : c.textSecondary),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    final all = s.docsFor(null).where((d) => people.any((m) => m.id == d.memberId)).toList();
    final docs = all.where((d) => _matches(s, d)).toList();
    final review = docs.where((d) => d.status == DocStatus.needsReview).toList();
    final rest = docs.where((d) => d.status != DocStatus.needsReview && d.status != DocStatus.processing).toList();
    final reading = docs.where((d) => d.status == DocStatus.processing).toList();
    final years = {for (final d in all) d.date.year}.toList()..sort((a, b) => b.compareTo(a));
    final byYear = <int, List<Doc>>{};
    for (final d in rest) {
      byYear.putIfAbsent(d.date.year, () => []).add(d);
    }
    final job = s.job;
    final jobOpen = job != null && job.done < job.total;

    return Column(children: [
      ScreenHeader(
        title: tr('Records'),
        big: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          const SettingsButton(),
          IconButton(tooltip: 'Import old reports', onPressed: () => pushPage(context, const BulkImportScreen()), icon: const Icon(Icons.library_add_rounded)),
        ]),
      ),
      Expanded(
        child: all.isEmpty
            ? Center(child: SingleChildScrollView(child: EmptyState(icon: Icons.description_rounded, message: 'Upload your first lab report to see trends', detail: 'PDFs, photos and WhatsApp files work.', buttonLabel: 'Upload report', onButton: () => pushPage(context, const UploadScreen()))))
            : ListView(padding: const EdgeInsets.fromLTRB(kSide, 8, kSide, 32), children: staggered([
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search records',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: search.text.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close_rounded), onPressed: () => setState(search.clear)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    if (people.length > 1) ...[
                      _filter<String>(context, 'Member', member, [(null, 'Everyone'), for (final m in people) (m.id, m.name)], (v) => setState(() => member = v)),
                      const SizedBox(width: 8),
                    ],
                    _filter<int>(context, 'Year', year, [(null, 'All years'), for (final y in years) (y, '$y')], (v) => setState(() => year = v)),
                    const SizedBox(width: 8),
                    _filter<DocKind>(context, 'Type', type, [(null, 'All types'), (DocKind.lab, 'Lab report'), (DocKind.prescription, 'Prescription'), (DocKind.other, 'Other')], (v) => setState(() => type = v)),
                  ]),
                ),
                const SizedBox(height: 12),
                if (jobOpen) ...[
                  BannerCard(icon: Icons.sync_rounded, tone: 'info', text: 'Importing ${job.byYear.keys.reduce((a, b) => a < b ? a : b)}–${job.byYear.keys.reduce((a, b) => a > b ? a : b)} · ${job.done} of ${job.total}', onTap: () => pushPage(context, const BulkImportScreen())),
                  const SizedBox(height: 12),
                ],
                if (review.isNotEmpty) ...[
                  Row(children: [
                    const Expanded(child: Text('Needs review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                    Container(
                      constraints: const BoxConstraints(minWidth: 28),
                      height: 28,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(999)),
                      child: Text('${review.length}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [for (var i = 0; i < review.length; i++) ...[if (i > 0) const Divider1(), DocRow(doc: review[i], showMember: people.length > 1)]])),
                  const SizedBox(height: 16),
                ],
                for (final y in (byYear.keys.toList()..sort((a, b) => b.compareTo(a)))) ...[
                  Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('$y', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [for (var i = 0; i < byYear[y]!.length; i++) ...[if (i > 0) const Divider1(), DocRow(doc: byYear[y]![i], showMember: people.length > 1)]])),
                  const SizedBox(height: 16),
                ],
                if (reading.isNotEmpty)
                  BannerCard(icon: Icons.description_rounded, tone: 'info', text: 'Reading ${reading.length} report${reading.length == 1 ? '' : 's'} in the background…', trailing: TextLink('Open', onTap: () => pushPage(context, const UploadScreen()))),
                if (docs.isEmpty)
                  Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('Nothing matches your search or filters.', style: TextStyle(fontSize: 15, color: c.textSecondary)))),
              ])),
      ),
    ]);
  }
}
