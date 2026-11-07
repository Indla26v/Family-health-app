import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/features.dart';
import '../data/models.dart';
import '../data/store.dart';

/// Opens the full-screen reminder when a dose notification is tapped.
final navigatorKey = GlobalKey<NavigatorState>();

/// Local, offline dose reminders. Every call is guarded: reminders failing must
/// never take the app down (e.g. on web, or when the user denies permission).
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String payload)? onOpen;

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) onOpen?.call(p);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('Reminders.init failed: $e');
    }
  }

  /// Payload of the notification that cold-started the app, if any.
  static Future<String?> launchPayload() async {
    if (!_ready) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) return d?.notificationResponse?.payload;
    } catch (_) {}
    return null;
  }

  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ok = await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      return ok ?? true;
    } catch (e) {
      debugPrint('Reminders.requestPermission failed: $e');
      return false;
    }
  }

  static int _id(String medId, DoseTime t) => (medId.hashCode ^ (t.hour * 60 + t.minute) * 7919) & 0x3fffffff;

  /// One-off reminder a few minutes from now ("Snooze 10 min").
  static Future<void> snooze(Medicine m, DoseTime t, int minutes) async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        id: (_id(m.id, t) + 1) & 0x3fffffff,
        title: 'Medicine time: ${m.label}',
        body: 'Snoozed reminder',
        scheduledDate: tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes)),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('doses', 'Medicine reminders', importance: Importance.max, priority: Priority.high, category: AndroidNotificationCategory.alarm, fullScreenIntent: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'dose:${m.id}:${t.hour}:${t.minute}',
      );
    } catch (e) {
      debugPrint('Reminders.snooze failed: $e');
    }
  }

  /// Clears and re-creates one repeating daily notification per scheduled dose
  /// for the people this phone is responsible for.
  static Future<void> reschedule(AppStore s) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!kMedicinesEnabled) return; // no dose alarms while medicines are hidden
      final who = s.members.map((m) => m.id).toSet();
      final now = tz.TZDateTime.now(tz.local);
      for (final m in s.meds.where((m) => m.active && who.contains(m.memberId))) {
        final person = s.member(m.memberId);
        for (final t in m.times) {
          var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
          if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
          final food = switch (m.food) { Food.before => 'before food', Food.after => 'after food', Food.any => '' };
          final body = [if (person != null) person.name, if (food.isNotEmpty) food].join(' · ');
          Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
                id: _id(m.id, t),
                title: 'Medicine time: ${m.label}',
                body: body.isEmpty ? 'Time for your medicine' : body,
                scheduledDate: at,
                notificationDetails: const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'doses',
                    'Medicine reminders',
                    channelDescription: 'Reminds you to take medicines on time',
                    importance: Importance.max,
                    priority: Priority.high,
                    category: AndroidNotificationCategory.alarm,
                    fullScreenIntent: true,
                    visibility: NotificationVisibility.public,
                  ),
                  iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
                ),
                androidScheduleMode: mode,
                matchDateTimeComponents: DateTimeComponents.time,
                payload: 'dose:${m.id}:${t.hour}:${t.minute}',
              );
          try {
            await go(AndroidScheduleMode.exactAllowWhileIdle);
          } catch (_) {
            await go(AndroidScheduleMode.inexactAllowWhileIdle);
          }
        }
      }
    } catch (e) {
      debugPrint('Reminders.reschedule failed: $e');
    }
  }
}

/// Speaks the medicine name; Telugu when the phone has a Telugu voice.
class Voice {
  static final FlutterTts _tts = FlutterTts();
  static bool _init = false;

  static Future<void> speak(String telugu, String english, {bool preferTelugu = true}) async {
    try {
      if (!_init) {
        _init = true;
        await _tts.setSpeechRate(.42);
      }
      final te = preferTelugu && (await _tts.isLanguageAvailable('te-IN') == true);
      await _tts.setLanguage(te ? 'te-IN' : 'en-IN');
      await _tts.speak(te ? telugu : english);
    } catch (e) {
      debugPrint('Voice.speak failed: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
