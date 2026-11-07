import 'package:flutter/material.dart';

import '../../core/features.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/sync_refresh.dart';
import 'appointment_form.dart';
import 'family.dart';
import 'health.dart';
import 'log_reading.dart';
import 'medicine_form.dart';
import 'records.dart';
import 'today.dart';
import 'upload.dart';

/// Bottom navigation: Today · Health · (+) · Records · Family.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  bool _sheetOpen = false;

  Future<void> _openFab() async {
    final c = context.c;
    setState(() => _sheetOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, String hint, Widget Function() page) => ListTile(
          minTileHeight: 64,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: IconBadge(icon, size: 44),
          title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          subtitle: Text(hint, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page(), fullscreenDialog: true));
          },
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: staggered([
              item(Icons.upload_file_rounded, 'Upload report', 'PDF or photos of a report', () => const UploadScreen()),
              item(Icons.monitor_heart_rounded, 'Log reading', 'BP, sugar, weight, oxygen', () => const LogReadingScreen()),
              if (kMedicinesEnabled) item(Icons.medication_rounded, 'Add medicine', 'With schedule and photo', () => const MedicineFormScreen()),
              if (kAppointmentsEnabled) item(Icons.calendar_month_rounded, 'Add appointment', 'Doctor visit or check-up', () => const AppointmentFormScreen()),
              const SizedBox(height: 12),
            ]),
          ),
        );
      },
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = watchStore(context);
    final c = context.c;
    final pages = <Widget>[
      for (final p in [TodayScreen(onSeeRecords: () => setState(() => tab = 2)), const HealthScreen(), const RecordsScreen(), const FamilyScreen()]) SyncRefresh(child: p),
    ];
    final review = s.reviewCount;
    const dur = Duration(milliseconds: 260);

    Widget navItem(int i, IconData off, IconData on, String label, {int badge = 0}) {
      final sel = tab == i;
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: badge > 0 ? '$label, $badge need review' : label,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => tab = i),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              // Large text: shrink to fit the bar instead of overflowing it.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        AnimatedContainer(
                          duration: dur,
                          curve: kEaseOut,
                          width: sel ? 60 : 40,
                          height: 30,
                          decoration: BoxDecoration(gradient: sel ? c.softGradient : null, color: sel ? null : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                          child: AnimatedScale(
                            scale: sel ? 1.08 : 1,
                            duration: dur,
                            curve: Curves.easeOutBack,
                            child: Icon(sel ? on : off, size: 22, color: sel ? c.accent : c.textSecondary),
                          ),
                        ),
                        if (badge > 0)
                          Positioned(
                            top: -6,
                            right: sel ? -2 : 4,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.danger,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: c.surface, width: 2),
                              ),
                              child: Text(
                                '$badge',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: dur,
                      style: TextStyle(fontSize: 12, height: 15 / 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? c.text : c.textSecondary),
                      child: Text(tr(label)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: FadeIndexedStack(index: tab, children: pages),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: .12), blurRadius: 24, offset: const Offset(0, -6))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                navItem(0, Icons.today_outlined, Icons.today_rounded, 'Today'),
                navItem(1, Icons.insights_outlined, Icons.insights_rounded, 'Health'),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'Add',
                      child: Pressable(
                        scale: .9,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          elevation: 3,
                          shadowColor: c.accent2.withValues(alpha: .35),
                          child: Ink(
                            decoration: BoxDecoration(gradient: c.gradient, borderRadius: BorderRadius.circular(20)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _openFab,
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: AnimatedRotation(
                                  turns: _sheetOpen ? .125 : 0,
                                  duration: dur,
                                  curve: kEaseOut,
                                  child: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                navItem(2, Icons.folder_outlined, Icons.folder_rounded, 'Records', badge: review),
                navItem(3, Icons.group_outlined, Icons.group_rounded, 'Family'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
