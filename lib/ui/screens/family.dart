import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'emergency.dart';
import 'profile_edit.dart';
import 'today.dart';


class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  String? id;

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final people = s.visibleMembers;
    // The person tapped in the list, else whoever uses this phone.
    final m = people.firstWhere((x) => x.id == id, orElse: () => people.firstWhere((x) => x.id == s.currentUser.id, orElse: () => people.first));
    final w = s.latestVital(m.id, VitalType.weight);
    final bmi = (w != null && m.heightCm != null && m.heightCm! > 0) ? w.a / ((m.heightCm! / 100) * (m.heightCm! / 100)) : null;

    Widget kv(String k, String? v, {String placeholder = '[Add]', VoidCallback? onTap}) => InkWell(
          onTap: onTap ?? () => pushPage(context, ProfileEditScreen(memberId: m.id)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 128, child: Text(k, style: TextStyle(fontSize: 15, color: c.textSecondary))),
                Expanded(child: Text(v == null || v.isEmpty ? placeholder : v, textAlign: TextAlign.right, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: v == null || v.isEmpty ? c.textSecondary.withValues(alpha: .8) : c.text))),
              ]),
            ),
          ),
        );

    return Column(children: [
      ScreenHeader(title: tr('Family'), big: true, trailing: const SettingsButton()),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(kSide, 8, kSide, 32), children: staggered([
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) const Divider1(),
                InkWell(
                  onTap: () => setState(() => id = people[i].id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Row(children: [
                      MemberAvatar(people[i], size: 48),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(people[i].name, style: TextStyle(fontSize: 17, fontWeight: people[i].id == m.id ? FontWeight.w800 : FontWeight.w600)),
                          Text('${people[i].age} yrs · ${people[i].bloodLabel}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                        ]),
                      ),
                      Icon(people[i].id == m.id ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: people[i].id == m.id ? c.accent : c.textSecondary),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          BigButton(label: 'Add family member', secondary: true, icon: Icons.person_add_rounded, onTap: () => pushPage(context, const ProfileEditScreen())),
          const SizedBox(height: 12),
          SurfaceCard(
            onTap: () => pushPage(context, EmergencyScreen(memberId: m.id)),
            child: Row(children: [
              const IconBadge(Icons.qr_code_2_rounded),
              const SizedBox(width: 14),
              Expanded(child: Text(tr('Emergency card'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right_rounded, color: c.textSecondary),
            ]),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(children: [
              Row(children: [
                MemberAvatar(m, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: AppText.titleLarge),
                    Text('${m.age} yrs • ${m.bloodLabel}${w == null ? '' : ' • ${w.a.toStringAsFixed(2)} kg'}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
                  ]),
                ),
                TextLink(tr('Edit'), onTap: () => pushPage(context, ProfileEditScreen(memberId: m.id))),
              ]),
              const SizedBox(height: 8),
              const Divider1(),
              kv('Blood group', m.bloodGroup),
              const Divider1(),
              kv('Height', m.heightCm == null ? null : fmtHeight(m.heightCm!), placeholder: '[Add height]'),
              const Divider1(),
              kv('Weight', w == null ? null : '${w.a.toStringAsFixed(2)} kg · ${ago(w.at)}', placeholder: 'Log your weight'),
              const Divider1(),
              kv('BMI', bmi?.toStringAsFixed(2), placeholder: 'Add height to see'),
              const Divider1(),
              kv('ABHA number', m.abha, placeholder: '[ABHA number]'),
              const Divider1(),
              kv('Insurance', m.insurance, placeholder: '[Insurer · policy no.]'),
              const Divider1(),
              kv('Allergies', m.allergies, placeholder: 'None recorded'),
              const Divider1(),
              kv('Family history', m.familyHistory, placeholder: '[Add]'),
            ]),
          ),
        ])),
      ),
    ]);
  }
}
