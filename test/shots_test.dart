// Renders every screen to PNG files under build/shots using the real seed
// data. Run with: flutter test test/shots_test.dart
// (Not a pass/fail visual test; it exists so each screen can be eyeballed.)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_health/core/strings.dart';
import 'package:family_health/core/theme.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/data/store.dart';
import 'package:family_health/ui/screens/adherence.dart';
import 'package:family_health/ui/screens/appointment_form.dart';
import 'package:family_health/ui/screens/appointments.dart';
import 'package:family_health/ui/screens/bp_detail.dart';
import 'package:family_health/ui/screens/bulk_import.dart';
import 'package:family_health/ui/screens/diabetes_detail.dart';
import 'package:family_health/ui/screens/emergency.dart';
import 'package:family_health/ui/screens/arrange_cards.dart';
import 'package:family_health/ui/screens/health.dart';
import 'package:family_health/ui/screens/lock_screen.dart';
import 'package:family_health/ui/screens/log_reading.dart';
import 'package:family_health/ui/screens/manual_entry.dart';
import 'package:family_health/ui/screens/medicine_form.dart';
import 'package:family_health/ui/screens/medicines.dart';
import 'package:family_health/ui/screens/parse_failed.dart';
import 'package:family_health/ui/screens/profile_edit.dart';
import 'package:family_health/ui/screens/records.dart';
import 'package:family_health/ui/screens/reminder_screen.dart';
import 'package:family_health/ui/screens/review.dart';
import 'package:family_health/ui/screens/settings.dart';
import 'package:family_health/ui/screens/shell.dart';
import 'package:family_health/ui/screens/family.dart';
import 'package:family_health/ui/screens/test_trend.dart';
import 'package:family_health/ui/screens/upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:family_health/ui/screens/onboarding.dart';
import 'package:family_health/ui/screens/who_uses.dart';
import 'package:family_health/ui/screens/login_screen.dart';

import 'support/sample_data.dart';

Future<void> _loadFonts() async {
  const root = 'C:/src/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String f) async => ByteData.sublistView(await File('$root/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('roboto-regular.ttf'))
    ..addFont(bytes('roboto-medium.ttf'))
    ..addFont(bytes('roboto-bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
}

void main() {
  late AppStore store, empty;
  final out = Directory('build/shots')..createSync(recursive: true);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    empty = await AppStore.load();
    store = await AppStore.load();
    seedDemoData(store);
  });

  Future<void> shot(WidgetTester t, String name, Widget page, {double h = 844, bool dark = false, AppStore? s}) async {
    debugPrint('SHOT $name');
    t.view.physicalSize = Size(390 * 2, h * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<AppStore>.value(
      value: s ?? store,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(dark ? Brightness.dark : Brightness.light),
          builder: (context, child) {
            final scale = (s ?? store).prefs.largeText ? 1.2 : 1.0;
            return MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!);
          },
          home: page,
        ),
      ),
    ));
    // Let entrance animations (up to ~0.8 s with stagger) finish before capturing.
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() async {
      final obj = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await obj.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('all screens', (t) async {
    final doc = store.docs.firstWhere((d) => d.status == DocStatus.needsReview && d.lab == 'Apollo Clinic');
    final failed = store.docs.firstWhere((d) => d.status == DocStatus.failed);

    await shot(t, '00_onboarding', const OnboardingScreen(), s: empty);
    final me = Member(id: 'me', name: 'Ravi', initial: 'R', age: 28, bloodGroup: '', sex: Sex.male, role: Role.admin, color: empty.nextColor());
    empty.addMember(me);
    empty.addMember(Member(id: 'amma', name: 'Amma', initial: 'A', age: 54, bloodGroup: 'O+', sex: Sex.female, role: Role.simple, color: empty.nextColor(), conditions: ['diabetes', 'bp']));
    empty.prefs
      ..deviceUserId = 'me'
      ..setupDone = true;
    await shot(t, '00b_fresh_today', const HomeShell(), s: empty);
    empty.selectedId = 'amma';
    await shot(t, '00c_fresh_health', _tab(const HealthScreen()), s: empty, h: 1300);
    await shot(t, '00d_fresh_records', _tab(const RecordsScreen()), s: empty);
    await shot(t, '01_lock', const LockScreen());
    await shot(t, '02_today_admin', const HomeShell(), h: 1100);
    store.prefs.deviceUserId = 'son';
    await shot(t, '04_log_reading', const LogReadingScreen(memberId: 'father'));
    await shot(t, '05_reminder', ReminderScreen(dose: store.dosesOn(DateTime.now(), memberId: 'father').first));
    await shot(t, '06_health', _tab(const HealthScreen()), h: 1700);
    await shot(t, '06_health_dark', _tab(const HealthScreen()), h: 1100, dark: true);
    await shot(t, '06b_arrange_cards', const ArrangeCardsScreen(memberId: 'father'), h: 1100);
    await shot(t, '07_diabetes', const DiabetesDetailScreen(memberId: 'father'), h: 2200);
    await shot(t, '08_trend_ldl', const TestTrendScreen(memberId: 'father', testKey: 'ldl'), h: 1100);
    await shot(t, '09_bp', const BpDetailScreen(memberId: 'father'), h: 1500);
    await shot(t, '10_records', _tab(const RecordsScreen()), h: 1300);
    await shot(t, '11_upload', const UploadScreen());
    await shot(t, '12_review', ReviewScreen(docId: doc.id), h: 1700);
    await shot(t, '13_bulk', const BulkImportScreen(), h: 1000);
    await shot(t, '14_parse_failed', ParseFailedScreen(docId: failed.id));
    await shot(t, '15_medicines', const MedicinesScreen(memberId: 'father'), h: 1300);
    await shot(t, '16_medicine_form', const MedicineFormScreen(memberId: 'father'), h: 1100);
    await shot(t, '17_adherence', const AdherenceScreen(memberId: 'father'), h: 1300);
    await shot(t, '18_appointments', const AppointmentsScreen(), h: 1300);
    await shot(t, '19_appt_form', const AppointmentFormScreen(), h: 1000);
    await shot(t, '20_family', _tab(const FamilyScreen()), h: 1700);
    await shot(t, '21_emergency', const EmergencyScreen(memberId: 'father'), h: 1500);
    await shot(t, '22_settings', const SettingsScreen(), h: 1500);
    await shot(t, '23_profile_edit', const ProfileEditScreen(memberId: 'father'), h: 1800);
    await shot(t, '24_manual', const ManualEntryScreen(memberId: 'daughter'));
    await shot(t, '25_today_admin_dark', const HomeShell(), h: 1100, dark: true);
    await shot(t, '28_who_uses', const WhoUsesScreen());
    await shot(t, '29_login', const LoginScreen());
    await shot(t, '30_signup', const SignUpScreen());

    Lang.code = 'te';
    store.prefs.largeText = true;
    store.prefs.deviceUserId = 'son';
    await shot(t, '27_reminder_te', ReminderScreen(dose: store.dosesOn(DateTime.now(), memberId: 'father').first));
    Lang.code = 'en';
    store.prefs.largeText = false;
  });
}

Widget _tab(Widget w) => Scaffold(body: SafeArea(child: w));
