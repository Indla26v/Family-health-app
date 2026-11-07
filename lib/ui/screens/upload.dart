import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/importer.dart';
import '../../services/process_upload.dart';
import '../widgets/common.dart';
import 'manual_entry.dart';
import 'review.dart';

class PickedFile {
  PickedFile(this.name, this.bytes, {this.photos});
  final String name;
  final Uint8List bytes;

  /// Pages photographed or picked as photos: read with OCR; [bytes] is their combined PDF.
  final List<Uint8List>? photos;
}

/// Source → member → reading → result.
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, this.memberId, this.photosFirst = false, this.shared});
  final String? memberId;

  /// Files shared to the app from Photos, WhatsApp…: skip choosing a source.
  final List<PickedFile>? shared;

  /// Open the photo picker straight away (e.g. "Pick photos again" for an unreadable scan).
  final bool photosFirst;
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  int step = 0;
  List<PickedFile> files = [];
  String? memberId;
  final outcomes = <UploadOutcome>[];
  int done = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    memberId = widget.memberId;
    if (widget.photosFirst) WidgetsBinding.instance.addPostFrameCallback((_) => _gallery());
    if (widget.shared != null) WidgetsBinding.instance.addPostFrameCallback((_) => _afterPick(widget.shared!));
  }

  Future<void> _files() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
      if (picked.isEmpty) return;
      final list = <PickedFile>[];
      for (final f in picked) {
        list.add(PickedFile(f.name, await f.readAsBytes()));
      }
      _afterPick(list);
    } catch (e) {
      if (mounted) toast(context, 'Could not open that file');
    }
  }

  /// Photos already on the phone (WhatsApp, gallery): all of them are one report's pages.
  Future<void> _gallery() async {
    try {
      final xs = await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 2200, maxHeight: 2200);
      if (xs.isEmpty) return;
      await _photos([for (final x in xs) await x.readAsBytes()]);
    } catch (e) {
      if (mounted) toast(context, 'Could not open your photos', ok: false);
    }
  }

  Future<void> _photos(List<Uint8List> pages) async {
    final pdf = await ImportService.pdfFromPhotos(pages);
    _afterPick([PickedFile('scan.pdf', pdf, photos: pages)]);
  }

  void _afterPick(List<PickedFile> list) {
    if (!mounted) return;
    final s = readStore(context);
    final people = s.visibleMembers;
    setState(() {
      files = list;
      if (people.length == 1) memberId = people.first.id;
      if (people.any((m) => m.id == memberId) && widget.memberId != null) {
        step = 2;
      } else {
        step = people.length == 1 ? 2 : 1;
      }
    });
    if (step == 2) _process();
  }

  Future<void> _process() async {
    final s = readStore(context);
    setState(() {
      step = 2;
      done = 0;
      outcomes.clear();
      error = null;
    });
    for (final f in files) {
      try {
        final o = await processUpload(s, memberId: memberId!, fileName: f.name, bytes: f.bytes, photos: f.photos);
        outcomes.add(o);
      } catch (e) {
        error = 'Something went wrong while reading ${f.name}.';
      }
      if (!mounted) return;
      setState(() => done++);
    }
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => step = 3);
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;

    Widget source(IconData icon, String title, String sub, VoidCallback onTap) => SurfaceCard(
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            IconBadge(icon, size: 52),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), Text(sub, style: TextStyle(fontSize: 14, color: c.textSecondary))])),
            Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          ]),
        );

    final total = outcomes.fold<int>(0, (a, o) => a + o.total);
    final auto = outcomes.fold<int>(0, (a, o) => a + o.auto);
    final check = outcomes.fold<int>(0, (a, o) => a + o.check);
    final unreadable = outcomes.where((o) => o.unreadable).length;
    final firstReview = outcomes.where((o) => o.doc.status == DocStatus.needsReview).firstOrNull;
    final m = s.member(memberId);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          ScreenHeader(
            title: 'Upload report',
            subtitle: 'Step ${step + 1} of 4',
            trailing: RoundIconButton(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.of(context).maybePop()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSide, vertical: 4),
            child: Row(children: [for (var i = 0; i < 4; i++) Expanded(child: Container(margin: EdgeInsets.only(right: i == 3 ? 0 : 6), height: 6, decoration: BoxDecoration(color: i <= step ? c.accent : c.border, borderRadius: BorderRadius.circular(3))))]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(kSide), children: [
              if (step == 0) ...[
                const Text('Where is the report?', style: AppText.titleLarge),
                const SizedBox(height: 16),
                source(Icons.folder_rounded, 'Files', 'PDF from WhatsApp, Gmail or your downloads', _files),
                const SizedBox(height: 12),
                source(Icons.photo_library_rounded, 'Photos', 'Photos of a paper report — pick all its pages', _gallery),
                const SizedBox(height: 20),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lock_rounded, size: 18, color: c.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Reports are read on this phone.', style: TextStyle(fontSize: 14, color: c.textSecondary, height: 20 / 14))),
                ]),
              ],
              if (step == 1) ...[
                const Text('Whose report is this?', style: AppText.titleLarge),
                const SizedBox(height: 16),
                for (final p in people) ...[
                  SurfaceCard(
                    onTap: () => setState(() => memberId = p.id),
                    borderColor: memberId == p.id ? c.accent : null,
                    color: memberId == p.id ? c.accentTint : null,
                    child: Row(children: [MemberAvatar(p, size: 48), const SizedBox(width: 14), Expanded(child: Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))), if (memberId == p.id) Icon(Icons.check_circle_rounded, color: c.accent)]),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                BigButton(label: 'Read ${files.length == 1 ? 'report' : '${files.length} reports'}', onTap: memberId == null ? null : _process),
                TextLink('Back', onTap: () => setState(() => step = 0)),
              ],
              if (step == 2) ...[
                const SizedBox(height: 24),
                Center(child: IconBadge(Icons.description_rounded, size: 88)),
                const SizedBox(height: 20),
                const Center(child: Text('Reading report…', style: AppText.titleLarge)),
                const SizedBox(height: 4),
                Center(child: Text(files.length == 1 ? files.first.name : '${files.length} files', style: TextStyle(fontSize: 15, color: c.textSecondary), overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 20),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: files.isEmpty ? null : done / files.length, minHeight: 10, color: c.accent, backgroundColor: c.border)),
                const SizedBox(height: 8),
                Center(child: Text(outcomes.isEmpty ? 'Looking for tests…' : 'Found $total tests', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                const SizedBox(height: 20),
                _check(c, done > 0, 'Pages read (${done > 0 ? outcomes.fold<int>(0, (a, o) => a + o.pages) : 0})'),
                _check(c, done > 0 && outcomes.isNotEmpty && !outcomes.any((o) => o.nameMismatch), done > 0 && outcomes.any((o) => o.nameMismatch) ? 'Name on report does not look like ${m?.name ?? 'this person'}' : (done > 0 && outcomes.every((o) => o.patient == null) ? 'No patient name found on the report' : 'Patient name matches ${m?.name ?? ''}'), warn: done > 0 && (outcomes.any((o) => o.nameMismatch) || outcomes.every((o) => o.patient == null))),
                _check(c, done >= files.length, 'Matching values to tests…'),
                const SizedBox(height: 16),
                Text('You can leave. Records shows a badge when done.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
              ],
              if (step == 3) ...[
                const SizedBox(height: 16),
                Center(child: Container(width: 88, height: 88, decoration: BoxDecoration(color: unreadable == outcomes.length && outcomes.isNotEmpty ? c.warnTint : c.accentTint, shape: BoxShape.circle), child: Icon(unreadable == outcomes.length && outcomes.isNotEmpty ? Icons.error_rounded : Icons.check_rounded, size: 48, color: unreadable == outcomes.length && outcomes.isNotEmpty ? c.warn : c.accent))),
                const SizedBox(height: 16),
                if (outcomes.isEmpty || unreadable == outcomes.length) ...[
                  Center(child: Text(error ?? 'Couldn’t read tests from this file', textAlign: TextAlign.center, style: AppText.titleLarge)),
                  const SizedBox(height: 8),
                  Text('No test values could be read. For photos, try again in good light with the whole page flat in the frame — or enter the values by hand.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                  const SizedBox(height: 20),
                  if (outcomes.isNotEmpty) BigButton(label: 'Enter values by hand', icon: Icons.edit_rounded, onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ManualEntryScreen(memberId: memberId!, docId: outcomes.first.doc.id)))),
                  const SizedBox(height: 8),
                  BigButton(label: 'Try another file', secondary: true, onTap: () => setState(() {
                        step = 0;
                        files = [];
                        outcomes.clear();
                      })),
                ] else ...[
                  Center(child: Text('$total tests read', style: AppText.titleLarge)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _count(c, '$auto', 'Auto-confirmed', Icons.check_circle_rounded, c.ok, c.okTint)),
                    const SizedBox(width: 12),
                    Expanded(child: _count(c, '$check', 'Need a look', Icons.error_rounded, c.warn, c.warnTint)),
                  ]),
                  if (outcomes.any((o) => o.nameMismatch)) ...[
                    const SizedBox(height: 12),
                    BannerCard(icon: Icons.error_rounded, tone: 'warn', text: 'The name on this report does not look like ${m?.name ?? 'this person'}. Nothing was confirmed automatically.'),
                  ],
                  const SizedBox(height: 24),
                  if (check > 0 && firstReview != null)
                    BigButton(label: 'Review $check ${check == 1 ? 'value' : 'values'}', onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ReviewScreen(docId: firstReview.doc.id))))
                  else
                    BigButton(label: 'Done', onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 4),
                  Center(child: TextLink('Later', onTap: () => Navigator.of(context).maybePop())),
                ],
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _check(AppPalette c, bool on, String text, {bool warn = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(on ? (warn ? Icons.error_rounded : Icons.check_circle_rounded) : Icons.schedule_rounded, size: 22, color: on ? (warn ? c.warn : c.ok) : c.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, color: on ? c.text : c.textSecondary))),
        ]),
      );

  Widget _count(AppPalette c, String n, String label, IconData icon, Color fg, Color bg) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [Text(n, style: const TextStyle(fontSize: 34, height: 48 / 40, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 18, color: fg), const SizedBox(width: 6), Flexible(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)))])]),
      );
}
