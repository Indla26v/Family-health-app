import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/features.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/reread.dart';
import 'doc_viewer.dart';
import 'manual_entry.dart';
import 'medicine_form.dart';
import 'records.dart';
import 'today.dart';

/// All documents waiting for review.
class ReviewListScreen extends StatelessWidget {
  const ReviewListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final docs = s.reviewDocs().where((d) => s.visibleMembers.any((m) => m.id == d.memberId)).toList();
    return PageBody(
      header: const ScreenHeader(title: 'Needs review', back: true),
      children: [
        if (docs.isEmpty)
          const EmptyState(icon: Icons.check_circle_rounded, message: 'Nothing to review', detail: 'Reports that need a look appear here.')
        else
          SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [for (var i = 0; i < docs.length; i++) ...[if (i > 0) const Divider1(), DocRow(doc: docs[i])]])),
      ],
    );
  }
}

/// Extracted values for one report: original on top (collapsible), values below,
/// low-confidence rows highlighted, sticky "Confirm N values".
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.docId});
  final String docId;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool showPdf = true, confirmed = false, reading = false;
  String? editing;
  final ctl = TextEditingController();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final d = s.doc(widget.docId);
    if (d == null) return PageBody(header: const ScreenHeader(title: 'Review values', back: true), children: const [EmptyState(icon: Icons.description_rounded, message: 'This report was removed')]);
    final m = s.member(d.memberId);
    final rows = s.labsOfDoc(d.id);
    final pending = rows.where((r) => !r.confirmed).toList();
    final toCheck = rows.where((r) => r.lowConfidence || r.checkNote.isNotEmpty).length;
    final isRx = d.kind == DocKind.prescription;
    // Opened from a report that was already reviewed, to fix or add a value.
    final reviewed = d.status == DocStatus.parsed && pending.isEmpty && !confirmed;
    // Show uncertain rows first.
    rows.sort((a, b) => (b.lowConfidence ? 1 : 0).compareTo(a.lowConfidence ? 1 : 0));

    /// One value as a compact row: name and status, the reference range and any
    /// note in small type, then the value (tap to edit), ✓ to confirm it and 🗑.
    Widget row(LabResult r) {
      final t = testByKey(r.testKey);
      final st = t == null || m == null ? null : labStatus(t, r.value, m.sex);
      final isEdit = editing == r.id;
      final low = !r.confirmed && (r.lowConfidence || r.checkNote.isNotEmpty);
      final name = t?.name ?? r.testKey;
      final sub = [if (r.refText.isNotEmpty) 'Ref ${r.refText}', if (r.rawName.isNotEmpty && r.rawName.toLowerCase() != name.toLowerCase()) '“${r.rawName}”'].join(' · ');
      void edit() => setState(() {
            editing = r.id;
            ctl.text = t == null ? '${r.value}' : fmtVal(t, r.value);
          });
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
        decoration: BoxDecoration(color: low ? c.warnTint : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (st != null) StatusPill.info(st),
              ]),
              if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.textSecondary))),
              if (r.checkNote.isNotEmpty && !r.confirmed) Padding(padding: const EdgeInsets.only(top: 2), child: Text(r.checkNote, style: TextStyle(fontSize: 12.5, color: c.warn, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(width: 6),
          if (isEdit)
            SizedBox(
              width: 84,
              child: TextField(
                controller: ctl,
                autofocus: true,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: AppText.numberLarge.copyWith(fontSize: 17),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                onSubmitted: (_) => _commit(s, r),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Edit $name, ${t == null ? r.value : fmtVal(t, r.value)} ${r.unit}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: edit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
                  child: Text(t == null ? '${r.value}' : fmtVal(t, r.value), style: AppText.numberLarge.copyWith(fontSize: 16)),
                ),
              ),
            ),
          SizedBox(width: 46, child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(r.unit, maxLines: 2, style: TextStyle(fontSize: 11.5, color: c.textSecondary)))),
          // ✓ saves an edit, or confirms this one value.
          if (isEdit || !r.confirmed)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isEdit ? 'Save value' : 'Confirm $name',
              icon: Icon(Icons.check_circle_outline_rounded, color: c.accent, size: 26),
              onPressed: () {
                if (isEdit) {
                  _commit(s, r);
                } else {
                  _confirmOne(s, d, r);
                }
              },
            )
          else
            Padding(padding: const EdgeInsets.symmetric(horizontal: 11), child: Tooltip(message: 'Confirmed', child: Icon(Icons.check_circle_rounded, color: c.ok, size: 26))),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove $name',
            icon: Icon(Icons.delete_outline_rounded, color: c.textSecondary, size: 22),
            onPressed: () {
              s.removeResult(r.id);
              toast(context, 'Removed $name', ok: true);
            },
          ),
        ]),
      );
    }

    return PageBody(
      header: ScreenHeader(
        title: isRx ? 'Prescription' : (reviewed ? 'Edit values' : 'Review values'),
        subtitle: '${d.lab} · ${fmtDate(d.date)} · ${m?.name ?? ''}',
        back: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          reading
              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
              : RoundIconButton(
                  icon: Icons.document_scanner_rounded,
                  label: 'Read again',
                  onTap: () async {
                    await rereadDoc(context, d, onStart: () => setState(() => reading = true));
                    if (mounted) setState(() => reading = false);
                  },
                ),
          const SizedBox(width: 8),
          RoundIconButton(icon: Icons.delete_outline_rounded, label: 'Delete report', onTap: () => _deleteDoc(s, d)),
        ]),
      ),
      padBottom: 24,
      bottom: confirmed || (reviewed && !isRx)
          ? BigButton(label: confirmed ? 'Added to trends' : 'Done', icon: Icons.check_circle_rounded, onTap: () => Navigator.of(context).maybePop())
          : (isRx && rows.isEmpty)
              ? BigButton(label: 'Mark as reviewed', onTap: () {
                  d.status = DocStatus.parsed;
                  s.changed();
                  toast(context, 'Marked as reviewed', ok: true);
                  Navigator.of(context).maybePop();
                })
              : BigButton(
                  label: pending.isEmpty ? 'Mark as reviewed' : 'Confirm ${pending.length} ${pending.length == 1 ? 'value' : 'values'}',
                  icon: Icons.check_rounded,
                  onTap: () {
                    s.confirmDoc(d.id);
                    HapticFeedback.mediumImpact();
                    toast(context, pending.isEmpty ? 'Marked as reviewed' : 'Values added to trends', ok: true);
                    setState(() => confirmed = true);
                  },
                ),
      children: [
        if (reading) BannerCard(icon: Icons.document_scanner_rounded, text: 'Reading ${d.pages > 1 ? 'all ${d.pages} pages' : 'the report'} again… this can take a minute. Keep the app open.'),
        InkWell(
          onTap: () => setState(() => showPdf = !showPdf),
          child: Row(children: [
            Icon(Icons.description_rounded, color: c.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('Original report${d.pages > 1 ? ' · ${d.pages} pages' : ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            TextButton(onPressed: () => setState(() => showPdf = !showPdf), child: Text(showPdf ? 'Hide' : 'Show', style: const TextStyle(fontSize: 15))),
          ]),
        ),
        if (showPdf) ReportPreview(doc: d, height: 240),
        if (d.note.isNotEmpty)
          BannerCard(icon: Icons.event_rounded, tone: 'warn', text: d.note, trailing: TextLink('Set date', onTap: () => _setDate(s, d)))
        else
          Row(children: [
            Icon(Icons.event_rounded, size: 20, color: c.textSecondary),
            const SizedBox(width: 8),
            Expanded(child: Text('Report date · ${fmtDate(d.date)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            TextLink('Change', onTap: () => _setDate(s, d)),
          ]),
        if (reviewed && !isRx) Text('Tap a value to correct it, or add a test the reading missed.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
        if (confirmed)
          BannerCard(icon: Icons.check_circle_rounded, tone: 'ok', text: 'Values added to ${m?.name ?? 'their'} trends', onTap: () => Navigator.of(context).maybePop())
        else if (isRx && rows.isEmpty)
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Prescription saved', style: AppText.title),
              const SizedBox(height: 4),
              if (kMedicinesEnabled) ...[
                Text('Add its medicines to get reminders.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
                TextLink('Add a medicine', icon: Icons.add_rounded, onTap: () => pushPage(context, MedicineFormScreen(memberId: d.memberId))),
              ] else
                Text('Open it any time from Records.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
            ]),
          )
        else ...[
          Row(children: [
            Expanded(child: Text('${rows.length} ${rows.length == 1 ? 'test' : 'tests'} found', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (toCheck > 0) StatusPill(label: '$toCheck to check', tone: 'warn'),
          ]),
          if (rows.isEmpty) Text('No values read. Add them below.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
          if (rows.isNotEmpty)
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
              child: Column(children: [
                for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 6, thickness: 1, indent: 10, endIndent: 10, color: c.border), row(rows[i])],
              ]),
            ),
          BigButton(label: 'Add a test by hand', secondary: true, icon: Icons.add_rounded, onTap: () => pushPage(context, ManualEntryScreen(memberId: d.memberId, docId: d.id))),
        ],
        Center(child: TextLink('Delete this report', icon: Icons.delete_outline_rounded, onTap: () => _deleteDoc(s, d))),
      ],
    );
  }

  /// ✓ on one row: this value is right, it joins the trends. When it was the last
  /// one waiting, the report counts as reviewed.
  void _confirmOne(AppStore s, Doc d, LabResult r) {
    r
      ..confirmed = true
      ..confidence = 1
      ..checkNote = '';
    if (s.labsOfDoc(d.id).every((l) => l.confirmed)) d.status = DocStatus.parsed;
    s.changed();
    HapticFeedback.selectionClick();
    toast(context, 'Confirmed ${testByKey(r.testKey)?.name ?? r.testKey}', ok: true);
  }

  /// Sets the report's date (and every value's), e.g. when the page had none or it was read wrong.
  Future<void> _setDate(AppStore s, Doc d) async {
    final now = DateTime.now();
    final dt = await showDatePicker(context: context, initialDate: d.date.isAfter(now) ? now : d.date, firstDate: DateTime(2000), lastDate: now, helpText: 'Date on the report');
    if (dt == null) return;
    d.date = dt;
    d.note = '';
    for (final l in s.labsOfDoc(d.id)) {
      l.date = dt;
    }
    s.changed();
    if (mounted) toast(context, 'Report date saved', ok: true);
  }

  Future<void> _deleteDoc(AppStore s, Doc d) async {
    if (!await confirmDialog(context, 'Delete this report?', 'The report and all its values will be removed.')) return;
    s.deleteDoc(d.id);
    if (!mounted) return;
    toast(context, 'Report deleted', ok: true);
    Navigator.of(context).maybePop();
  }

  void _commit(AppStore s, LabResult r) {
    final v = double.tryParse(ctl.text);
    if (v != null) {
      r.value = v;
      r.confidence = 1;
      r.checkNote = '';
      s.changed();
      toast(context, 'Value saved', ok: true);
    } else {
      toast(context, 'Enter the value as a number', ok: false);
    }
    setState(() => editing = null);
  }
}
