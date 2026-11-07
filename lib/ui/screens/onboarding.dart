import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'profile_edit.dart';
import 'settings.dart' show PinSetupSheet;

/// First run: welcome → about you → your family → app lock.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late int step = readStore(context).members.isEmpty ? 0 : 2;

  Future<void> _aboutYou() async {
    final s = readStore(context);
    final me = await Navigator.of(context).push<Member>(MaterialPageRoute(builder: (_) => const ProfileEditScreen(title: 'About you')));
    if (me == null) return;
    s.setPref((p) => p
      ..deviceUserId = me.id
      ..deviceUserAsked = true);
    setState(() => step = 2);
  }

  Future<void> _add() async {
    await Navigator.of(context).push<Member>(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
    setState(() {});
  }

  Future<void> _finish({required bool lock}) async {
    final s = readStore(context);
    if (lock) {
      final pin = await showModalBottomSheet<String>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const PinSetupSheet());
      if (pin == null) return;
      s.setPin(pin);
      s.prefs.lockEnabled = true;
    }
    s.unlocked = true;
    s.setPref((p) => p.setupDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;

    Widget page({IconData? icon, required String title, required String body, required List<Widget> children, Widget? bottom}) => Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kSide, 12, kSide, 0),
                child: Row(children: [
                  for (var i = 0; i < 4; i++) Expanded(child: Container(margin: EdgeInsets.only(right: i == 3 ? 0 : 6), height: 6, decoration: BoxDecoration(color: i <= step ? c.accent : c.border, borderRadius: BorderRadius.circular(3)))),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
                  Align(alignment: Alignment.centerLeft, child: icon == null ? const AppLogo(size: 64) : IconBadge(icon, size: 64)),
                  const SizedBox(height: 20),
                  Text(title, style: const TextStyle(fontSize: 24, height: 34 / 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(body, style: TextStyle(fontSize: 16, height: 26 / 18, color: c.textSecondary)),
                  const SizedBox(height: 24),
                  ...children,
                ]),
              ),
              if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: bottom),
            ]),
          ),
        );

    switch (step) {
      case 0:
        return page(
          title: 'Family Health',
          body: 'Reports, medicines, BP and sugar for the whole family.',
          bottom: BigButton(label: 'Get started', onTap: () => setState(() => step = 1)),
          children: [
            Text(tr('Language'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              height: 52,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                for (final (k, l) in [('en', 'English'), ('te', 'తెలుగు')])
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => s.setLang(k),
                      child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: s.prefs.lang == k ? c.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Text(l, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: s.prefs.lang == k ? c.accent : c.textSecondary))),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            SwitchRow(icon: Icons.format_size_rounded, title: 'Large text mode', subtitle: 'Everything 20% bigger', value: s.prefs.largeText, onChanged: (v) => s.setPref((p) => p.largeText = v)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_rounded, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text('Private to your family. Not medical advice.', style: TextStyle(fontSize: 14, color: c.textSecondary, height: 20 / 14))),
            ]),
          ],
        );
      case 1:
        return page(
          icon: Icons.person_rounded,
          title: 'First, about you',
          body: 'You’ll manage the family’s records.',
          bottom: BigButton(label: 'Add my details', icon: Icons.arrow_forward_rounded, onTap: _aboutYou),
          children: [TextLink('Back', onTap: () => setState(() => step = 0))],
        );
      case 2:
        return page(
          icon: Icons.group_rounded,
          title: 'Add your family',
          body: 'Add the people you look after.',
          bottom: BigButton(label: s.members.length > 1 ? 'Continue' : 'Skip for now', onTap: () => setState(() => step = 3)),
          children: [
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                for (var i = 0; i < s.members.length; i++) ...[
                  if (i > 0) const Divider1(),
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfileEditScreen(memberId: s.members[i].id))).then((_) => setState(() {})),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 72),
                      child: Row(children: [
                        MemberAvatar(s.members[i], size: 44),
                        const SizedBox(width: 12),
                        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${s.members[i].name}${s.members[i].id == s.prefs.deviceUserId ? ' (you)' : ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('${s.members[i].age} yrs', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                        ])),
                        Icon(Icons.edit_rounded, color: c.textSecondary),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            BigButton(label: 'Add a family member', secondary: true, icon: Icons.person_add_rounded, onTap: _add),
          ],
        );
      default:
        return page(
          icon: Icons.lock_rounded,
          title: 'Lock the app?',
          body: 'Fingerprint or PIN to open the app.',
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            BigButton(label: 'Set a PIN', icon: Icons.lock_rounded, onTap: () => _finish(lock: true)),
            const SizedBox(height: 4),
            TextLink('Not now', onTap: () => _finish(lock: false)),
          ]),
          children: [Text('You can change this later in Settings.', style: TextStyle(fontSize: 15, color: c.textSecondary))],
        );
    }
  }
}
