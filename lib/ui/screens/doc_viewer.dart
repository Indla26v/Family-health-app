import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/importer.dart';
import '../../services/sync_service.dart';
import '../widgets/common.dart';
import '../widgets/reread.dart';
import '../widgets/motion.dart';
import 'manual_entry.dart';
import 'review.dart';
import 'today.dart';

void openDocument(BuildContext context, String docId) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocViewerScreen(docId: docId)));
}

/// Shows the original file of a report. A report added on the web or another phone
/// is downloaded once and kept here. The preview is a still first page; tapping
/// it opens [ReportReader] with every page, pinch-zoom and a page counter.
class ReportPreview extends StatefulWidget {
  const ReportPreview({super.key, required this.doc, this.height = 280});
  final Doc doc;
  final double height;
  @override
  State<ReportPreview> createState() => _ReportPreviewState();
}

class _ReportPreviewState extends State<ReportPreview> {
  Uint8List? bytes;
  bool loading = true;
  String problem = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      problem = '';
    });
    var b = await ImportService.load(widget.doc.id, widget.doc.filePath);
    var why = '';
    if (b == null && mounted) {
      final sync = context.read<SyncService?>();
      if (sync != null) (b, why) = await sync.fetchOriginal(widget.doc);
    }
    if (!mounted) return;
    setState(() {
      bytes = b;
      loading = false;
      problem = b == null ? (why.isEmpty ? 'Original file not on this phone.' : why) : '';
    });
  }

  bool get _pdf {
    final d = widget.doc;
    if (d.filePath != null) return ImportService.isPdf(d.filePath!);
    return !d.isImage;
  }

  void _open() {
    if (bytes == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReportReader(doc: widget.doc, bytes: bytes!, pdf: _pdf)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = widget.doc;
    Widget body;
    if (loading) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 10),
          Text('Opening the original…', style: TextStyle(fontSize: 14, color: c.textSecondary)),
        ]),
      );
    } else if (bytes == null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(d.isImage ? Icons.image_rounded : Icons.description_rounded, size: 44, color: c.textSecondary),
            const SizedBox(height: 8),
            Text('${d.lab} · ${fmtDate(d.date)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(problem, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 4),
            TextLink('Try again', icon: Icons.refresh_rounded, onTap: _load),
          ]),
        ),
      );
    } else {
      // A still preview: scrolling the page around it must not be swallowed by the PDF.
      final still = IgnorePointer(
        child: _pdf
            ? PdfViewer.data(bytes!, sourceName: '${d.id}-preview', params: PdfViewerParams(backgroundColor: c.surfaceAlt, margin: 6))
            : Image.memory(bytes!, fit: BoxFit.contain, width: double.infinity),
      );
      final pages = d.pages > 1 ? 'View all ${d.pages} pages' : 'View full size';
      body = Semantics(
        button: true,
        label: 'Open report, $pages',
        child: GestureDetector(
          onTap: _open,
          child: Stack(fit: StackFit.expand, children: [
            still,
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(gradient: c.gradient, borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 4))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.open_in_full_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(pages, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          ]),
        ),
      );
    }
    return Pressable(
      enabled: bytes != null,
      child: Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(20)),
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey('$loading${bytes != null}'), child: body)),
      ),
    );
  }
}

/// Full-screen reader: every page of a PDF (scroll, pinch to zoom) or a photo.
class ReportReader extends StatefulWidget {
  const ReportReader({super.key, required this.doc, required this.bytes, required this.pdf});
  final Doc doc;
  final Uint8List bytes;
  final bool pdf;
  @override
  State<ReportReader> createState() => _ReportReaderState();
}

class _ReportReaderState extends State<ReportReader> {
  final _controller = PdfViewerController();
  int? _page;
  int? _count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = widget.doc;
    return Scaffold(
      backgroundColor: c.surfaceAlt,
      body: SafeArea(
        child: Column(children: [
          ScreenHeader(
            title: d.lab,
            subtitle: fmtDate(d.date),
            back: true,
            trailing: widget.pdf && _count != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999)),
                    child: Text('${_page ?? 1} / $_count', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  )
                : null,
          ),
          Expanded(
            child: widget.pdf
                ? PdfViewer.data(
                    widget.bytes,
                    sourceName: '${d.id}-reader',
                    controller: _controller,
                    params: PdfViewerParams(
                      backgroundColor: c.surfaceAlt,
                      margin: 8,
                      // Scrollable-style flings (the default zoom-viewer physics stop quickly and feel slow).
                      scrollPhysics: PdfViewerParams.getScrollPhysics(context),
                      onViewerReady: (doc, _) => setState(() {
                        _count = doc.pages.length;
                        _page = 1;
                      }),
                      onPageChanged: (p) => setState(() => _page = p ?? _page),
                      viewerOverlayBuilder: (context, size, _) => [
                        PdfViewerScrollThumb(
                          controller: _controller,
                          orientation: ScrollbarOrientation.right,
                          thumbSize: const Size(44, 26),
                          thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.text.withValues(alpha: .75), borderRadius: BorderRadius.circular(8)),
                            child: Text('${pageNumber ?? ''}', style: TextStyle(color: c.bg, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  )
                : InteractiveViewer(minScale: 1, maxScale: 6, child: Center(child: Image.memory(widget.bytes, fit: BoxFit.contain))),
          ),
        ]),
      ),
    );
  }
}

class DocViewerScreen extends StatefulWidget {
  const DocViewerScreen({super.key, required this.docId});
  final String docId;
  @override
  State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  bool reading = false;

  /// Read again, with a spinner while it works (a long scan takes a while). When
  /// the new values need a look, the review screen opens in place of this one.
  Future<void> _reread(Doc d) async {
    final o = await rereadDoc(context, d, onStart: () => setState(() => reading = true));
    if (!mounted) return;
    setState(() => reading = false);
    if (o != null && o.doc.status == DocStatus.needsReview) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ReviewScreen(docId: o.doc.id)));
    }
  }

  void _edit(Doc d) => pushPage(context, ReviewScreen(docId: d.id));
  void _add(Doc d) => pushPage(context, ManualEntryScreen(memberId: d.memberId, docId: d.id));

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final d = s.doc(widget.docId);
    if (d == null) {
      return PageBody(header: const ScreenHeader(title: 'Report', back: true), children: const [EmptyState(icon: Icons.description_rounded, message: 'This report was removed')]);
    }
    final m = s.member(d.memberId);
    final results = s.labsOfDoc(d.id);
    return PageBody(
      header: ScreenHeader(
        title: d.lab,
        subtitle: '${fmtDate(d.date)} · ${m?.name ?? ''}',
        back: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          reading
              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
              : RoundIconButton(icon: Icons.document_scanner_rounded, label: 'Read again', onTap: () => _reread(d)),
          const SizedBox(width: 8),
          RoundIconButton(icon: Icons.delete_outline_rounded, label: 'Delete report', onTap: () => _delete(context, s, d)),
        ]),
      ),
      children: [
        if (reading) BannerCard(icon: Icons.document_scanner_rounded, text: 'Reading ${d.pages > 1 ? 'all ${d.pages} pages' : 'the report'} again… this can take a minute. Keep the app open.'),
        ReportPreview(key: ValueKey(d.filePath), doc: d, height: 420),
        Row(children: [
          Expanded(child: Text('${results.length} ${results.length == 1 ? 'test' : 'tests'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          if (results.isNotEmpty) ...[
            RoundIconButton(icon: Icons.edit_rounded, label: 'Edit values', onTap: () => _edit(d)),
            const SizedBox(width: 8),
          ],
          RoundIconButton(icon: Icons.add_rounded, label: 'Add a missed test', onTap: () => _add(d)),
        ]),
        if (results.isNotEmpty)
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (var i = 0; i < results.length; i++) ...[
                if (i > 0) const Divider1(),
                Builder(builder: (_) {
                  final r = results[i];
                  final t = testByKey(r.testKey);
                  final st = t == null || m == null ? null : labStatus(t, r.value, m.sex);
                  return Semantics(
                    button: true,
                    label: 'Edit ${t?.name ?? r.testKey}',
                    child: InkWell(
                      onTap: () => _edit(d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          Expanded(child: Text(t?.name ?? r.testKey, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                          Text('${t == null ? r.value : fmtVal(t, r.value)} ${r.unit}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                          const SizedBox(width: 8),
                          if (st != null) StatusPill.info(st),
                        ]),
                      ),
                    ),
                  );
                }),
              ],
            ]),
          )
        else
          Text('No values were recorded from this file.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
        BigButton(label: 'Add a missed test', secondary: true, icon: Icons.add_rounded, onTap: () => _add(d)),
        Center(child: TextLink('Delete this report', icon: Icons.delete_outline_rounded, onTap: () => _delete(context, s, d))),
      ],
    );
  }

  Future<void> _delete(BuildContext context, AppStore s, Doc d) async {
    if (!await confirmDialog(context, 'Delete this report?', 'The report and all its values will be removed.')) return;
    s.deleteDoc(d.id);
    if (!context.mounted) return;
    toast(context, 'Report deleted', ok: true);
    Navigator.of(context).pop();
  }
}
