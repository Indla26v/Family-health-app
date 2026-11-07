import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../widgets/common.dart';

/// Add a new family member (memberId == null) or edit an existing one.
/// When adding, pops with the created [Member].
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, this.memberId, this.title});
  final String? memberId;
  final String? title;
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final Member? m = widget.memberId == null ? null : readStore(context).member(widget.memberId);
  late final name = TextEditingController(text: m?.name ?? '');
  late final full = TextEditingController(text: m?.fullName ?? '');
  late final age = TextEditingController(text: m == null || m!.age == 0 ? '' : '${m!.age}');
  late final height = TextEditingController(text: m?.heightCm == null ? '' : _fmtNum(m!.heightCm!));
  late final (int, int)? _ftIn0 = m?.heightCm == null ? null : feetInches(m!.heightCm!);
  late final feet = TextEditingController(text: _ftIn0 == null ? '' : '${_ftIn0.$1}');
  late final inches = TextEditingController(text: _ftIn0 == null ? '' : '${_ftIn0.$2}');

  /// Height is entered in feet + inches (the family's habit) or in cm; stored in cm.
  bool _feet = true;
  late final abha = TextEditingController(text: m?.abha ?? '');
  late final insurance = TextEditingController(text: m?.insurance ?? '');
  late final allergies = TextEditingController(text: m?.allergies ?? '');
  late final history = TextEditingController(text: m?.familyHistory ?? '');
  late String blood = m?.bloodGroup ?? '';
  late Sex sex = m?.sex ?? Sex.male;
  late final Set<String> conds = {...?m?.conditions};
  late final List<Contact> _c = m?.contacts ?? const [];
  late final List<TextEditingController> cName = [for (var i = 0; i < 2; i++) TextEditingController(text: i < _c.length ? _c[i].name : '')];
  late final List<TextEditingController> cRel = [for (var i = 0; i < 2; i++) TextEditingController(text: i < _c.length ? _c[i].relation : '')];
  late final List<TextEditingController> cPhone = [for (var i = 0; i < 2; i++) TextEditingController(text: i < _c.length ? _c[i].phone : '')];
  bool _tried = false;

  @override
  void dispose() {
    for (final t in [name, full, age, height, feet, inches, abha, insurance, allergies, history, ...cName, ...cRel, ...cPhone]) {
      t.dispose();
    }
    super.dispose();
  }

  static String _fmtNum(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  /// The entered height in cm (exact: 5′11″ → 180.34), or null when left empty.
  double? get _cm {
    if (!_feet) return double.tryParse(height.text.trim());
    final f = feet.text.trim(), i = inches.text.trim();
    if (f.isEmpty && i.isEmpty) return null;
    return ((int.tryParse(f) ?? 0) * 12 + (int.tryParse(i) ?? 0)) * 2.54;
  }

  /// Empty, or a plausible height (the web app refuses anything else).
  bool get _heightOk {
    if (_feet) {
      if ((int.tryParse(inches.text.trim()) ?? 0) > 11) return false;
    } else if (height.text.trim().isNotEmpty && double.tryParse(height.text.trim()) == null) {
      return false;
    }
    final h = _cm;
    return h == null || (h >= 30 && h <= 250);
  }

  void _switchUnit(bool toFeet) {
    if (toFeet == _feet) return;
    final h = _cm;
    setState(() {
      _feet = toFeet;
      if (h == null) return;
      if (toFeet) {
        final (f, i) = feetInches(h);
        feet.text = '$f';
        inches.text = '$i';
      } else {
        height.text = _fmtNum((h * 100).roundToDouble() / 100);
      }
    });
  }

  void _save() {
    setState(() => _tried = true);
    final n = name.text.trim();
    final a = int.tryParse(age.text.trim());
    if (n.isEmpty || a == null || a <= 0 || a > 120 || !_heightOk) return;
    final s = readStore(context);
    final target = m ?? Member(id: s.newId('m'), name: n, initial: n[0].toUpperCase(), age: a, bloodGroup: blood, sex: sex, role: Role.admin, color: s.nextColor());
    target
      ..name = n
      ..initial = n[0].toUpperCase()
      ..fullName = full.text.trim()
      ..age = a
      ..heightCm = _cm == null ? null : (_cm! * 100).roundToDouble() / 100
      ..abha = abha.text.trim()
      ..insurance = insurance.text.trim()
      ..allergies = allergies.text.trim()
      ..familyHistory = history.text.trim()
      ..bloodGroup = blood
      ..sex = sex
      ..role = Role.admin // everyone has the same, full access
      ..conditions = conditionDefs.map((d) => d.id).where(conds.contains).toList()
      ..contacts = [for (var i = 0; i < 2; i++) if (cName[i].text.trim().isNotEmpty || cPhone[i].text.trim().isNotEmpty) Contact(cName[i].text.trim(), cRel[i].text.trim(), cPhone[i].text.trim())];
    if (m == null) {
      s.addMember(target);
    } else {
      s.ensureCheckups(target);
      s.changed();
    }
    toast(context, m == null ? 'Added ${target.name}' : 'Profile saved', ok: true);
    Navigator.of(context).pop(target);
  }

  Future<void> _delete() async {
    final s = readStore(context);
    if (await confirmDialog(context, 'Remove ${m!.name}?', 'All their records will be deleted.', yes: 'Remove')) {
      s.deleteMember(m!.id);
      if (!mounted) return;
      toast(context, 'Removed ${m!.name}', ok: true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = watchStore(context);
    final isNew = m == null;
    final canDelete = !isNew && m!.id != s.currentUser.id;
    final ageVal = int.tryParse(age.text.trim());

    Widget label(String t) => Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary));
    Widget field(String l, TextEditingController ctl, {String? hint, TextInputType? type, int lines = 1, String? error, List<TextInputFormatter>? fmt, TextCapitalization cap = TextCapitalization.sentences}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label(l),
          const SizedBox(height: 6),
          TextField(controller: ctl, keyboardType: type, inputFormatters: fmt, textCapitalization: cap, minLines: lines, maxLines: lines, onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 16), decoration: InputDecoration(hintText: hint, errorText: error)),
        ]);

    return PageBody(
      header: ScreenHeader(title: widget.title ?? (isNew ? 'Add family member' : 'Edit profile'), subtitle: isNew ? null : m!.name, back: true),
      spacing: 16,
      bottom: BigButton(label: isNew ? 'Save' : 'Save profile', onTap: _save),
      children: [
        field('Name shown in the app', name, hint: 'e.g. Amma, Nanna, Priya', cap: TextCapitalization.words, error: _tried && name.text.trim().isEmpty ? 'Please enter a name' : null),
        field('Full name (optional)', full, hint: 'As printed on lab reports', cap: TextCapitalization.words),
        field('Age', age, type: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly], error: _tried && (ageVal == null || ageVal <= 0 || ageVal > 120) ? 'Enter age' : null),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: label('Height (optional)')),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, selectedBackgroundColor: c.accentTint, selectedForegroundColor: c.accent),
              segments: const [ButtonSegment(value: true, label: Text('ft · in')), ButtonSegment(value: false, label: Text('cm'))],
              selected: {_feet},
              onSelectionChanged: (v) => _switchUnit(v.first),
            ),
          ]),
          const SizedBox(height: 6),
          if (_feet)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: TextField(controller: feet, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 16), decoration: const InputDecoration(hintText: '5', suffixText: 'ft'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: inches, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 16), decoration: InputDecoration(hintText: '6', suffixText: 'in', errorText: _heightOk ? null : '0–11 inches'))),
            ])
          else
            TextField(controller: height, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 16), decoration: InputDecoration(hintText: 'e.g. 165', suffixText: 'cm', errorText: _heightOk ? null : 'Enter height in cm, e.g. 165')),
          if (_heightOk && _cm != null)
            Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(fmtHeight(_cm!), style: TextStyle(fontSize: 13, color: c.textSecondary))),
        ]),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label('Blood group'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: blood,
                isExpanded: true,
                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                style: TextStyle(fontSize: 16, color: c.text),
                items: [const DropdownMenuItem(value: '', child: Text('Not known')), for (final b in ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']) DropdownMenuItem(value: b, child: Text(b))],
                onChanged: (v) => setState(() => blood = v ?? blood),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label('Sex (lab ranges)'),
              const SizedBox(height: 6),
              DropdownButtonFormField<Sex>(initialValue: sex, isExpanded: true, decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)), style: TextStyle(fontSize: 16, color: c.text), items: const [DropdownMenuItem(value: Sex.male, child: Text('Male')), DropdownMenuItem(value: Sex.female, child: Text('Female'))], onChanged: (v) => setState(() => sex = v ?? sex)),
            ]),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label('Health conditions to track'),
          const SizedBox(height: 4),
          Text('Optional. Each gets its own card.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in conditionDefs)
              FilterChip(
                label: Text(d.en, style: const TextStyle(fontSize: 14)),
                selected: conds.contains(d.id),
                onSelected: (v) => setState(() => v ? conds.add(d.id) : conds.remove(d.id)),
                showCheckmark: true,
                selectedColor: c.accentTint,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ]),
        ]),
        field('Allergies', allergies, hint: 'e.g. Penicillin — leave empty if none', lines: 2),
        if (!isNew) ...[
          field('ABHA number', abha, hint: '14-digit ABHA number', type: TextInputType.number),
          field('Insurance', insurance, hint: 'Insurer · policy no.'),
          field('Family history', history, hint: 'e.g. Diabetes in parents', lines: 2),
        ],
        const Text('Emergency contacts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        for (var i = 0; i < 2; i++)
          SurfaceCard(
            child: Column(children: [
              Row(children: [Expanded(child: field('Name', cName[i], cap: TextCapitalization.words)), const SizedBox(width: 10), Expanded(child: field('Relation', cRel[i], hint: 'e.g. Son'))]),
              const SizedBox(height: 10),
              field('Phone number', cPhone[i], type: TextInputType.phone),
            ]),
          ),
        if (canDelete) BigButton(label: 'Remove ${m!.name}', secondary: true, icon: Icons.person_remove_rounded, onTap: _delete),
      ],
    );
  }
}
