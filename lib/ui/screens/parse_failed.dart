import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../services/importer.dart';
import '../../services/process_upload.dart';
import '../widgets/common.dart';
import 'doc_viewer.dart';
import 'manual_entry.dart';
import 'today.dart';
import 'upload.dart';

/// "Couldn't read this page" with Retry / Enter manually / Scan again.
class ParseFailedScreen extends StatefulWidget {
  const ParseFailedScreen({super.key, required this.docId});
  final String docId;
  @override
  State<ParseFailedScreen> createState() => _ParseFailedScreenState();
}

class _ParseFailedScreenState extends State<ParseFailedScreen> {
  bool busy = false;

  Future<void> _retry(Doc d) async {
    final s = readStore(context);
    setState(() => busy = true);
    final Uint8List? bytes = await ImportService.load(d.id, d.filePath);
    if (bytes == null) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, 'Original not stored. Scan the page again.');
      }
      return;
    }
    final name = d.filePath ?? (d.isImage ? 'scan.jpg' : 'report.pdf');
    final o = await processUpload(s, memberId: d.memberId, fileName: name, bytes: bytes, retry: d);
    if (!mounted) return;
    setState(() => busy = false);
    if (o.unreadable) {
      toast(context, 'Still couldn’t read it. Try entering the values by hand.');
    } else {
      Navigator.of(context).pop();
      toast(context, 'Read ${o.total} tests');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final d = s.doc(widget.docId);
    if (d == null) return PageBody(header: const ScreenHeader(title: 'Report', back: true), children: const [EmptyState(icon: Icons.description_rounded, message: 'This report was removed')]);
    final m = s.member(d.memberId);
    final rows = s.labsOfDoc(d.id);
    final page = d.failedPage;
    final server = s.prefs.serverHost.trim().isNotEmpty;

    return PageBody(
      header: ScreenHeader(title: d.lab, subtitle: '${m?.name ?? ''} · ${fmtDate(d.date)}', back: true),
      children: [
        ReportPreview(doc: d, height: 180),
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.cancel_rounded, color: c.danger),
              const SizedBox(width: 8),
              const Expanded(child: Text('Couldn’t read this page', style: AppText.title)),
            ]),
            const SizedBox(height: 6),
            Text(page == null ? 'The text on this file was too faint or blurred to read.' : 'Page $page looks blurred.${d.pages > 1 ? ' The other ${d.pages - 1} pages were read.' : ''}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: BigButton(label: busy ? 'Reading…' : 'Retry', icon: Icons.sync_rounded, secondary: true, onTap: busy ? null : () => _retry(d))),
              const SizedBox(width: 10),
              Expanded(child: BigButton(label: 'Enter manually', icon: Icons.edit_rounded, onTap: () => pushPage(context, ManualEntryScreen(memberId: d.memberId, docId: d.id)))),
            ]),
            const SizedBox(height: 4),
            Center(child: TextLink('Pick photos again', onTap: () => pushPage(context, UploadScreen(memberId: d.memberId, photosFirst: true)))),
          ]),
        ),
        if (rows.isNotEmpty) ...[
          Text(page == null ? 'Values read' : 'From pages 1–${page - 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider1(),
                Builder(builder: (_) {
                  final r = rows[i];
                  final t = testByKey(r.testKey);
                  final st = t == null || m == null ? null : labStatus(t, r.value, m.sex);
                  return SizedBox(
                    height: 64,
                    child: Row(children: [
                      Expanded(child: Text('${t?.name ?? r.testKey} · ${t == null ? r.value : fmtVal(t, r.value)} ${r.unit}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                      if (st != null) StatusPill.info(st),
                    ]),
                  );
                }),
              ],
            ]),
          ),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.save_rounded, size: 18, color: c.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(server ? 'Saved on this phone. Syncs when online.' : 'Saved on this phone.', style: TextStyle(fontSize: 14, color: c.textSecondary, height: 20 / 14))),
        ]),
      ],
    );
  }
}
