import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';

/// Asked once after each sign-in: whose phone is this? Health and Family then open on
/// that person (the Today page still shows everyone). It can be changed in Settings.
class WhoUsesScreen extends StatefulWidget {
  const WhoUsesScreen({super.key});
  @override
  State<WhoUsesScreen> createState() => _WhoUsesScreenState();
}

class _WhoUsesScreenState extends State<WhoUsesScreen> {
  String? picked;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.members;
    final sel = picked ?? s.currentUser.id;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.fromLTRB(kSide, 32, kSide, 24), children: [
              Icon(Icons.phone_android_rounded, size: 44, color: c.accent),
              const SizedBox(height: 12),
              const Text('Who uses this phone?', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Health and Family will open on this person. You can change it later in Settings.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.35)),
              const SizedBox(height: 24),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  for (var i = 0; i < people.length; i++) ...[
                    if (i > 0) const Divider1(),
                    Semantics(
                      button: true,
                      selected: people[i].id == sel,
                      child: InkWell(
                        onTap: () => setState(() => picked = people[i].id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 68),
                          child: Row(children: [
                            MemberAvatar(people[i], size: 44),
                            const SizedBox(width: 14),
                            Expanded(child: Text(people[i].name, style: TextStyle(fontSize: 17, fontWeight: people[i].id == sel ? FontWeight.w800 : FontWeight.w600))),
                            Icon(people[i].id == sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: people[i].id == sel ? c.accent : c.textSecondary),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
              BigButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                height: 52,
                onTap: () {
                  s.setPref((p) => p
                    ..deviceUserId = sel
                    ..deviceUserAsked = true);
                  s.selectedId = null; // Health and Family follow the person picked here
                  s.changed();
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
