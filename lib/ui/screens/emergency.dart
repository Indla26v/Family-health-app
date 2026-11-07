import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/strings.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../services/pdf_export.dart';
import '../widgets/common.dart';
import 'profile_edit.dart';
import 'today.dart';

/// Red-free, high-contrast card: name, age, blood group, conditions, medicines,
/// allergies, tap-to-call contacts, and a QR code that works offline.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key, this.memberId});
  final String? memberId;
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  String? memberId;

  Future<void> _call(String phone) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok && mounted) toast(context, 'Could not start the call');
  }

  Future<void> _share(Member m) async {
    final s = readStore(context);
    final bytes = await buildEmergencyPdf(s, m);
    await FilePicker.saveFile(fileName: 'emergency-card-${m.name.toLowerCase()}.pdf', bytes: bytes, mimeType: 'application/pdf', dialogTitle: 'Save emergency card');
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    memberId ??= people.any((m) => m.id == widget.memberId) ? widget.memberId : (people.any((m) => m.id == s.currentUser.id) ? s.currentUser.id : people.first.id);
    final m = s.member(memberId)!;
    final meds = s.medsOf(m.id);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final paper = dark ? const Color(0xFF0B0F12) : Colors.white;

    Widget section(String label, String text) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label).toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: .6, color: ink.withValues(alpha: .65))),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(fontSize: 17, height: 26 / 19, fontWeight: FontWeight.w600, color: ink)),
          ]),
        );

    return PageBody(
      header: ScreenHeader(title: tr('Emergency card'), back: true, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            MemberPicker(members: people, selectedId: memberId, onSelect: (id) => setState(() => memberId = id)),
            IconButton(tooltip: 'Share', onPressed: () => _share(m), icon: Icon(Icons.share_rounded, size: 22, color: c.accent)),
          ])),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: ink, width: 2.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.medical_information_rounded, color: ink),
              const SizedBox(width: 8),
              Text('MEDICAL EMERGENCY', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1, color: ink)),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, style: TextStyle(fontSize: 26, height: 36 / 30, fontWeight: FontWeight.w800, color: ink)),
                  Text('${m.fullName.isEmpty ? '[Full name]' : m.fullName} · ${m.age} years', style: TextStyle(fontSize: 15, color: ink.withValues(alpha: .75))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [Text('BLOOD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: paper)), Text(m.bloodGroup.isEmpty ? '?' : m.bloodGroup, style: TextStyle(fontSize: 30, height: 40 / 34, fontWeight: FontWeight.w800, color: paper))]),
              ),
            ]),
            section('Conditions', m.conditions.isEmpty ? 'None listed' : m.conditions.map((x) => conditionById(x).en).join(' · ')),
            if (kMedicinesEnabled) section('Current medicines', meds.isEmpty ? 'None' : meds.map((x) => x.label).join(' · ')),
            section('Allergies', m.allergies.isEmpty ? '[None recorded]' : m.allergies),
            const SizedBox(height: 18),
            if (m.contacts.isEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: TextLink('Add emergency contacts', icon: Icons.call_rounded, onTap: () => pushPage(context, ProfileEditScreen(memberId: m.id)))),
            for (final k in m.contacts) ...[
              Semantics(
                button: true,
                label: 'Call ${k.name}',
                child: Material(
                  color: ink,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: k.phone.isEmpty ? () => pushPage(context, ProfileEditScreen(memberId: m.id)) : () => _call(k.phone),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Icon(Icons.call_rounded, color: paper),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Call ${k.name}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: paper)), Text('${k.relation} · ${k.phone.isEmpty ? '[add phone number]' : k.phone}', style: TextStyle(fontSize: 14, color: paper.withValues(alpha: .8)))])),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Center(
              child: Column(children: [
                Container(padding: const EdgeInsets.all(10), color: Colors.white, child: QrImageView(data: emergencyQrText(s, m), size: 172, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.M, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square), dataModuleStyle: const QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square), semanticsLabel: 'QR code with the emergency details')),
                const SizedBox(height: 8),
                Text('Scan to see this card. Works without internet.', style: TextStyle(fontSize: 14, color: ink.withValues(alpha: .75))),
              ]),
            ),
          ]),
        ),
        TextLink('Edit allergies and contacts', icon: Icons.edit_rounded, onTap: () => pushPage(context, ProfileEditScreen(memberId: m.id))),
        const SectionTitle('Home-screen widget'),
        // Preview of the card as it will look on the lock screen / home screen.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: ink, width: 2)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('EMERGENCY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: ink.withValues(alpha: .65))),
                Text(m.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
                Text('${m.bloodGroup.isEmpty ? '' : '${m.bloodGroup} · '}${m.conditions.take(2).map((x) => conditionById(x).en.replaceAll('Blood pressure', 'BP')).join(', ')}', style: TextStyle(fontSize: 14, color: ink.withValues(alpha: .8))),
              ]),
            ),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_rounded, size: 18, color: paper), const SizedBox(width: 6), Text('Call ${m.contacts.isEmpty ? '' : m.contacts.first.name}', style: TextStyle(fontWeight: FontWeight.w700, color: paper))])),
          ]),
        ),
        Text('Preview only. Home-screen widget coming later.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
      ],
    );
  }
}
