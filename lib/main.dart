import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/store.dart';
import 'services/api_client.dart';
import 'services/reminders.dart';
import 'services/share_inbox.dart';
import 'services/sync_service.dart';
import 'ui/app_root.dart';
import 'ui/screens/reminder_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.load();
  await TokenStore.instance.load();
  final sync = SyncService(store)..attach();
  await Reminders.init();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppStore>.value(value: store),
      ChangeNotifierProvider<SyncService>.value(value: sync),
    ],
    child: const FamilyHealthApp(),
  ));
  _wireReminders(store);
  ShareInbox.instance.init();
}

void _wireReminders(AppStore store) {
  var last = '';
  String sig() => '${store.prefs.deviceUserId}|${store.meds.where((m) => m.active).map((m) => '${m.id}:${m.times.map((t) => t.key).join(',')}').join(';')}';
  Future<void> sync() async {
    final s = sig();
    if (s == last) return;
    last = s;
    await Reminders.reschedule(store);
  }

  Reminders.onOpen = (payload) => openReminderFromPayload(store, payload);
  store.addListener(sync);
  sync();
  Reminders.launchPayload().then((p) {
    if (p != null) WidgetsBinding.instance.addPostFrameCallback((_) => openReminderFromPayload(store, p));
  });
}

class FamilyHealthApp extends StatelessWidget {
  const FamilyHealthApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>();
    final mode = switch (s.prefs.darkMode) { 'dark' => ThemeMode.dark, 'light' => ThemeMode.light, _ => ThemeMode.system };
    return MaterialApp(
      title: 'Family Health',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      // Compact text (x0.92); large-text mode: x1.2 on top, and on top of the system font scale.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = 0.92 * (s.prefs.largeText ? 1.2 : 1.0);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)), child: child!);
      },
      home: const AppRoot(),
    );
  }
}
