import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../widgets/common.dart';

/// Quick-log sheet: BP / Sugar / Weight / SpO2 with a big numeric keypad and an
/// instant status pill.
class LogReadingScreen extends StatefulWidget {
  const LogReadingScreen({super.key, this.memberId, this.mode = VitalType.bp});
  final String? memberId;
  final VitalType mode;
  @override
  State<LogReadingScreen> createState() => _LogReadingScreenState();
}

class _LogReadingScreenState extends State<LogReadingScreen> {
  late VitalType mode = widget.mode;
  String? memberId;
  String active = 'sys';
  bool afterMeal = false, saved = false;
  DateTime at = DateTime.now();
  final vals = <String, String>{'sys': '', 'dia': '', 'pulse': '', 'sugar': '', 'weight': '', 'spo2': ''};

  List<(String, String, String, int, int)> get fields => switch (mode) {
        VitalType.bp => [('sys', 'Systolic', 'mmHg', 50, 300), ('dia', 'Diastolic', 'mmHg', 30, 200), ('pulse', 'Pulse', 'beats/min', 30, 220)],
        VitalType.sugar => [('sugar', 'Sugar', 'mg/dL', 20, 700)],
        VitalType.weight => [('weight', 'Weight', 'kg', 10, 300)],
        VitalType.spo2 => [('spo2', 'Oxygen (SpO2)', '%', 50, 100)],
      };

  @override
  void initState() {
    super.initState();
    active = fields.first.$1;
  }

  double _v(String k) => double.tryParse(vals[k] ?? '') ?? 0;

  /// null = nothing entered yet; otherwise status; `bad` = number out of plausible bounds.
  (StatusInfo?, bool) _status() {
    switch (mode) {
      case VitalType.bp:
        if (vals['sys']!.isEmpty || vals['dia']!.isEmpty) return (null, false);
        if (!_inBounds('sys') || !_inBounds('dia') || _v('dia') >= _v('sys')) return (null, true);
        return (VitalRanges.bp(_v('sys'), _v('dia')), false);
      case VitalType.sugar:
        if (vals['sugar']!.isEmpty) return (null, false);
        if (!_inBounds('sugar')) return (null, true);
        return (VitalRanges.sugar(_v('sugar'), afterMeal), false);
      case VitalType.spo2:
        if (vals['spo2']!.isEmpty) return (null, false);
        if (!_inBounds('spo2')) return (null, true);
        return (VitalRanges.spo2(_v('spo2')), false);
      case VitalType.weight:
        if (vals['weight']!.isEmpty) return (null, false);
        if (!_inBounds('weight')) return (null, true);
        return (const StatusInfo(Level.none, 'No range'), false);
    }
  }

  bool _inBounds(String k) {
    final f = fields.firstWhere((e) => e.$1 == k);
    final v = _v(k);
    return v >= f.$4 && v <= f.$5;
  }

  void _press(String k) {
    HapticFeedback.selectionClick();
    final keys = fields.map((f) => f.$1).toList();
    setState(() {
      saved = false;
      final cur = vals[active] ?? '';
      if (k == 'del') {
        vals[active] = cur.isEmpty ? '' : cur.substring(0, cur.length - 1);
      } else if (k == 'next') {
        active = keys[(keys.indexOf(active) + 1) % keys.length];
      } else if (k == '.') {
        if (!cur.contains('.') && cur.isNotEmpty && cur.length < 5) vals[active] = '$cur.';
      } else if (cur.length < (mode == VitalType.weight ? 5 : 3)) {
        vals[active] = cur + k;
        // BP convenience: move to the next field after 3 digits (or two for diastolic/pulse once plausible).
        final auto = mode == VitalType.bp && vals[active]!.length == 3 && keys.indexOf(active) < keys.length - 1;
        if (auto) active = keys[keys.indexOf(active) + 1];
      }
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(at));
    if (t != null) setState(() => at = DateTime(at.year, at.month, at.day, t.hour, t.minute));
  }

  void _save() {
    final s = readStore(context);
    final (st, bad) = _status();
    if (st == null || bad) return;
    final id = s.newId('v');
    s.addVital(Vital(
      id: id,
      memberId: memberId!,
      type: mode,
      at: at,
      a: mode == VitalType.bp ? _v('sys') : _v(fields.first.$1),
      b: mode == VitalType.bp ? _v('dia') : 0,
      pulse: mode == VitalType.bp ? _v('pulse') : 0,
      afterMeal: mode == VitalType.sugar && afterMeal,
    ));
    HapticFeedback.mediumImpact();
    toast(context, 'Reading saved', ok: true);
    setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??= people.any((m) => m.id == widget.memberId) ? widget.memberId : (people.any((m) => m.id == s.selectedId) ? s.selectedId : people.first.id);
    final member = s.member(memberId);
    final (st, bad) = _status();
    final info = st;
    final note = switch (mode) {
      VitalType.bp => info == null ? '' : VitalRanges.bpNote(info),
      VitalType.sugar => info == null ? '' : VitalRanges.sugarNote(info),
      VitalType.spo2 => info == null ? '' : VitalRanges.spo2Note(info),
      VitalType.weight => info == null ? '' : 'Saved to the weight trend',
    };
    final modes = [(VitalType.bp, 'BP'), (VitalType.sugar, 'Sugar'), (VitalType.weight, 'Weight'), (VitalType.spo2, 'SpO2')];
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', mode == VitalType.weight ? '.' : 'next'];

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          ScreenHeader(
            title: tr('Log reading'),
            subtitle: 'Today · ${fmtDay(DateTime.now())}',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              RoundIconButton(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.of(context).maybePop()),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(kSide, 4, kSide, 16), children: [
              Row(children: [
                if (people.length > 1)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final m in people)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => setState(() => memberId = m.id),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
                                decoration: BoxDecoration(color: m.id == memberId ? c.accentTint : c.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: m.id == memberId ? c.accent : c.border)),
                                child: Row(children: [MemberAvatar(m, size: 34), const SizedBox(width: 8), Text(m.name, style: TextStyle(fontSize: 15, fontWeight: m.id == memberId ? FontWeight.w700 : FontWeight.w500))]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  )
                else
                  Expanded(child: Row(children: [MemberAvatar(member, size: 36), const SizedBox(width: 10), Text(member?.name ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))])),
                TextButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 20),
                  label: Text(DateUtils.isSameDay(at, DateTime.now()) && at.difference(DateTime.now()).inMinutes.abs() < 2 ? 'Now, ${fmtTime(at)}' : fmtTime(at), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.textSecondary),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                height: 52,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  for (final (m, l) in modes)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: mode == m,
                        label: l,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            mode = m;
                            active = fields.first.$1;
                            saved = false;
                          }),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: mode == m ? c.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                            child: Text(l, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: mode == m ? c.accent : c.textSecondary)),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              if (mode == VitalType.sugar) ...[
                const SizedBox(height: 12),
                Row(children: [
                  for (final (v, l) in [(false, 'Before breakfast'), (true, 'After meal')])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: v ? 0 : 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            afterMeal = v;
                            saved = false;
                          }),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: afterMeal == v ? c.accentTint : c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: afterMeal == v ? c.accent : c.border, width: 1.5)),
                            child: Text(tr(l), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 14),
              Row(children: [
                for (final f in fields)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: f == fields.last ? 0 : 8),
                      child: Semantics(
                        button: true,
                        label: '${tr(f.$2)} ${vals[f.$1]!.isEmpty ? 'empty' : vals[f.$1]} ${f.$3}',
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => active = f.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(color: f.$1 == active ? c.accentTint : c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: f.$1 == active ? c.accent : c.border, width: f.$1 == active ? 2 : 1)),
                            child: Column(children: [
                              Text(tr(f.$2), maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 18 / 14, fontWeight: FontWeight.w600, color: c.textSecondary)),
                              const SizedBox(height: 2),
                              FittedBox(child: Text(vals[f.$1]!.isEmpty ? '–' : vals[f.$1]!, style: AppText.displayNumber)),
                              Text(f.$3, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Row(key: ValueKey('${info?.word}$bad'), children: [
                  if (info != null) StatusPill.info(info) else StatusPill(label: bad ? 'Check the numbers' : 'Enter a value', tone: bad ? 'warn' : 'muted'),
                  const SizedBox(width: 12),
                  Expanded(child: Text(note, style: TextStyle(fontSize: 15, color: c.textSecondary))),
                ]),
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.15,
                children: [
                  for (final k in keys)
                    Semantics(
                      button: true,
                      label: switch (k) { 'del' => 'Delete', 'next' => 'Next field', '.' => 'Decimal point', _ => k },
                      excludeSemantics: true,
                      child: Material(
                        color: k == 'next' ? c.accentTint : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _press(k),
                          child: Center(
                            child: k == 'del'
                                ? Icon(Icons.backspace_outlined, color: c.text)
                                : Text(k == 'next' ? tr('Next') : k, style: TextStyle(fontSize: k == 'next' ? 18 : 23, fontWeight: FontWeight.w600, color: k == 'next' ? c.accent : c.text)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            child: saved
                ? BigButton(label: '${tr('Saved on phone')} · ${tr('Done')}', icon: Icons.check_circle_rounded, onTap: () => Navigator.of(context).maybePop())
                : BigButton(label: tr('Save reading'), onTap: (st == null || bad) ? null : _save),
          ),
        ]),
      ),
    );
  }
}
