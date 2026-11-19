import 'dart:io';

import 'package:family_health/core/strings.dart';
import 'package:family_health/core/theme.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/data/store.dart';
import 'package:family_health/services/app_update.dart';
import 'package:family_health/ui/screens/diabetes_detail.dart';
import 'package:family_health/ui/screens/bp_detail.dart';
import 'package:family_health/ui/screens/health.dart';
import 'package:family_health/ui/screens/log_reading.dart';
import 'package:family_health/ui/screens/reading_history.dart';
import 'package:family_health/ui/screens/shell.dart';
import 'package:family_health/ui/screens/test_trend.dart';
import 'package:family_health/ui/screens/today.dart';
import 'package:family_health/ui/screens/weight_trend.dart';
import 'package:family_health/ui/widgets/charts.dart';
import 'package:family_health/ui/widgets/common.dart';
import 'package:family_health/ui/widgets/trend_card.dart';
import 'package:family_health/ui/widgets/update_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_data.dart';

class _TestUpdateService extends AppUpdateService {
  void openingInstaller() {
    stage = UpdateStage.openingInstaller;
    notifyListeners();
  }
}

void main() {
  late AppStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final roboto = FontLoader('Roboto');
    for (final style in ['regular', 'medium', 'bold']) {
      roboto.addFont(
        File(
          'C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-$style.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await roboto.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await AppStore.load();
    seedEmptyFamily(store);
    store.selectedId = 'son'; // No conditions or reports are needed for logs.
  });

  Vital sugar(
    String id,
    double value, {
    bool after = false,
    String member = 'son',
    DateTime? at,
  }) => Vital(
    id: id,
    memberId: member,
    type: VitalType.sugar,
    at: at ?? DateTime(2026, 11, 14, 8),
    a: value,
    afterMeal: after,
  );

  Future<void> mount(
    WidgetTester t,
    Widget page, {
    double width = 430,
    double height = 1100,
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool reducedMotion = false,
    AppUpdateService? updates,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ChangeNotifierProvider<AppUpdateService?>.value(
              value: updates,
              child: page,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  void settleStore() =>
      store.saveNow(); // Cancel the store's debounced save timer.
  tearDown(() {
    settleStore();
    store.dispose();
  });

  testWidgets('Today, Health and logging fit narrow screens with larger Telugu text in dark mode', (t) async {
    store.addVital(sugar('fast', 99));
    Lang.code = 'te';
    addTearDown(() => Lang.code = 'en');
    for (final page in [const TodayScreen(), const HealthScreen(), const LogReadingScreen()]) {
      await mount(t, page, width: 320, height: 700, scale: 1.4, brightness: Brightness.dark);
      expect(t.takeException(), isNull);
    }
  });

  testWidgets(
    'an open reading history handles a family member removed by sync',
    (t) async {
      store.addVital(sugar('fast', 99));
      await mount(t, const ReadingHistoryScreen(memberId: 'son'));
      store.deleteMember('son');
      await t.pumpAndSettle();
      expect(find.text('This family member is no longer available'), findsOneWidget);
      expect(find.text('Fasting glucose 99 mg/dL'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Health plots a single weight reading and opens a zoomable graph',
    (t) async {
      store.addVital(
        Vital(
          id: 'weight',
          memberId: 'son',
          type: VitalType.weight,
          at: DateTime(2026, 11, 14),
          a: 72.5,
        ),
      );
      await mount(t, const HealthScreen());
      expect(find.byType(SmoothTrend), findsOneWidget);
      await t.tap(find.text('Weight'));
      await t.pumpAndSettle();
      expect(find.byType(WeightTrendScreen), findsOneWidget);
      expect(
        t
            .widget<TrendChart>(find.byType(TrendChart))
            .series
            .single
            .points
            .single
            .value,
        72.5,
      );

      final plot = find.descendant(
        of: find.byType(TrendChart),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter?.runtimeType.toString() == '_ChartPainter',
        ),
      );
      (double, double, double, double) bounds() {
        final dynamic geo =
            (t.widget<CustomPaint>(plot).painter as dynamic).geo;
        return (
          geo.xMin as double,
          geo.xMax as double,
          geo.yMin as double,
          geo.yMax as double,
        );
      }

      final full = bounds();
      await t.tap(find.byTooltip('Zoom in'));
      await t.pumpAndSettle();
      final zoomed = bounds();
      expect(zoomed.$2 - zoomed.$1, lessThan(full.$2 - full.$1));
      expect(zoomed.$4 - zoomed.$3, lessThan(full.$4 - full.$3));
      await t.dragFrom(t.getCenter(plot), const Offset(-70, 0));
      await t.pumpAndSettle();
      final horizontal = bounds();
      expect(horizontal.$1, greaterThan(zoomed.$1));
      await t.dragFrom(t.getCenter(plot), const Offset(0, -70));
      await t.pumpAndSettle();
      expect(bounds().$3, lessThan(horizontal.$3));
      await t.tap(find.text('Reset view'));
      await t.pumpAndSettle();
      expect(bounds(), full);

      final middle = t.getCenter(plot);
      final left = await t.startGesture(
        middle - const Offset(25, 0),
        pointer: 1,
      );
      final right = await t.startGesture(
        middle + const Offset(25, 0),
        pointer: 2,
      );
      for (final distance in [40.0, 55.0, 75.0]) {
        await left.moveTo(middle - Offset(distance, 0));
        await right.moveTo(middle + Offset(distance, 0));
        await t.pump();
      }
      await left.up();
      await right.up();
      await t.pumpAndSettle();
      final pinched = bounds();
      expect(pinched.$2 - pinched.$1, lessThan(full.$2 - full.$1));

      await t.tap(find.byTooltip('Chart style'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bar'));
      await t.pumpAndSettle();
      expect(bounds().$3, 0);
      expect(store.prefs.chartStyle, 'bar');
      await t.tap(find.byTooltip('Chart style'));
      await t.pumpAndSettle();
      await t.tap(find.text('Points'));
      await t.pumpAndSettle();
      expect(bounds(), full);
      store.saveNow();
      final reloaded = await AppStore.load();
      expect(reloaded.prefs.chartStyle, 'points');
      reloaded.dispose();
    },
  );

  for (final everyone in [false, true]) {
    testWidgets(
      'Today ${everyone ? 'everyone rows' : 'member cards'} open BP, fasting and post-meal graphs separately',
      (t) async {
        store.selectedId = everyone ? null : 'son';
        store.addVital(sugar('fast', 99));
        store.addVital(sugar('post', 145, after: true));
        store.addVital(
          Vital(
            id: 'bp',
            memberId: 'son',
            type: VitalType.bp,
            at: DateTime.now(),
            a: 120,
            b: 80,
          ),
        );
        await mount(t, const TodayScreen(), height: 1400);
        expect(find.text('Readings · 7d'), findsOneWidget);
        expect(find.text('To review'), findsOneWidget);
        expect(find.text('Upload report'), findsOneWidget);
        if (everyone) {
          await t.tap(find.text('Son'));
          await t.pumpAndSettle();
        }
        for (final (label, key, value) in [
          ('Blood pressure', 'bp', 120.0),
          ('Fasting glucose', 'fbs', 99.0),
          ('Post-meal glucose', 'ppbs', 145.0),
        ]) {
          await t.ensureVisible(find.text(label));
          await t.pumpAndSettle();
          await t.tap(find.text(label));
          await t.pumpAndSettle();
          expect(find.byType(LogReadingScreen), findsNothing);
          expect(find.byType(DiabetesDetailScreen), findsNothing);
          final chart = t.widget<TrendChart>(find.byType(TrendChart));
          if (key == 'bp') {
            expect(find.byType(BpDetailScreen), findsOneWidget);
            expect(chart.series.length, 2);
            expect(chart.series.first.points.single.value, value);
          } else {
            expect(
              t.widget<TestTrendScreen>(find.byType(TestTrendScreen)).testKey,
              key,
            );
            expect(chart.series.length, 1);
            expect(chart.series.single.points.single.value, value);
          }
          await t.tap(find.byIcon(Icons.arrow_back_rounded));
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
      },
    );
  }

  test(
    'merges only matching confirmed labs and home logs, retaining sources and times',
    () {
      store.labs.addAll([
        LabResult(
          id: 'lab',
          memberId: 'son',
          testKey: 'fbs',
          value: 95,
          unit: 'mg/dL',
          date: DateTime(2026, 11, 13),
          docId: 'report',
          lab: 'Lab',
        ),
        LabResult(
          id: 'pending',
          memberId: 'son',
          testKey: 'fbs',
          value: 180,
          unit: 'mg/dL',
          date: DateTime(2026, 11, 15),
          docId: 'pending-report',
          lab: 'Lab',
          confirmed: false,
        ),
      ]);
      store.addVital(sugar('post', 145, after: true));
      store.addVital(sugar('fast', 99));
      store.addVital(sugar('other-member', 200, member: 'father'));
      store.addVital(
        Vital(
          id: 'weight',
          memberId: 'son',
          type: VitalType.weight,
          at: DateTime(2026),
          a: 72,
        ),
      );
      final fasting = store.healthReadingsOf('son', 'fbs');
      expect(fasting.map((r) => r.id), ['lab', 'fast']);
      expect(fasting.first.docId, 'report');
      expect(fasting.last.docId, isNull);
      expect(fasting.last.date.hour, 8);
      expect(fasting.last.source, 'Home reading · fasting');
      expect(store.healthReadingsOf('son', 'ppbs').single.id, 'post');
      expect(store.healthReadingsOf('son', 'hba1c'), isEmpty);
      expect(store.resultsOf('son', 'fbs').length, 1);
      expect(store.healthTestKeysOf('son'), {'fbs', 'ppbs'});
    },
  );

  test(
    'deleting a home reading updates trends and survives reload without duplicating labs',
    () async {
      store.addVital(sugar('fast', 99));
      store.addVital(sugar('post', 145, after: true));
      store.saveNow();
      final reloaded = await AppStore.load();
      expect(reloaded.healthReadingsOf('son', 'fbs').single.value, 99);
      expect(reloaded.labs, isEmpty);
      reloaded.deleteVital('fast');
      expect(reloaded.healthReadingsOf('son', 'fbs'), isEmpty);
      expect(reloaded.healthReadingsOf('son', 'ppbs').single.value, 145);
      reloaded.saveNow();
      final again = await AppStore.load();
      expect(again.healthTestKeysOf('son'), {'ppbs'});
      reloaded.dispose();
      again.dispose();
    },
  );

  testWidgets(
    'saving fasting and post-meal sugar immediately updates Health without reports',
    (t) async {
      await mount(t, const HealthScreen());
      for (final (value, after) in [('99', false), ('145', true)]) {
        await t.tap(find.text('Log reading'));
        await t.pumpAndSettle();
        await t.tap(find.text('Sugar'));
        await t.pumpAndSettle();
        if (after) await t.tap(find.text('After meal'));
        for (final digit in value.split('')) {
          await t.tap(find.text(digit));
        }
        await t.pump();
        await t.tap(find.text('Save reading'));
        await t.pumpAndSettle();
        await t.pump(
          const Duration(seconds: 4),
        ); // Let the save toast clear the Done button.
        await t.pumpAndSettle();
        await t.tap(find.text('Saved on phone · Done'));
        await t.pumpAndSettle();
        expect(find.byType(LogReadingScreen), findsNothing);
      }
      final cards = t.widgetList<TrendCard>(find.byType(TrendCard)).toList();
      expect(
        cards.map((c) => c.title),
        containsAll(['Fasting glucose', 'Post-meal glucose']),
      );
      expect(
        cards
            .firstWhere((c) => c.title == 'Fasting glucose')
            .points
            .last
            .value,
        99,
      );
      expect(
        cards
            .firstWhere((c) => c.title == 'Post-meal glucose')
            .points
            .last
            .value,
        145,
      );
      expect(store.labs, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'home-only glucose appears in detail chart with time and no source-report link',
    (t) async {
      store.addVital(sugar('fast', 99));
      await mount(t, const TestTrendScreen(memberId: 'son', testKey: 'fbs'));
      final series = t
          .widget<TrendChart>(find.byType(TrendChart))
          .series
          .single;
      expect(series.points.single.value, 99);
      expect(series.points.single.docId, isNull);
      expect(find.text('Home reading · fasting'), findsNWidgets(2));
      expect(find.bySemanticsLabel('View source report'), findsNothing);
      expect(find.text('1 reading'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Diabetes shows a single home reading before any lab reports', (
    t,
  ) async {
    store.addVital(sugar('post', 145, after: true));
    await mount(t, const DiabetesDetailScreen(memberId: 'son'), height: 1600);
    expect(find.text('Daily sugar'), findsOneWidget);
    expect(find.text('Glucose readings'), findsOneWidget);
    final charts = t.widgetList<TrendChart>(find.byType(TrendChart)).toList();
    expect(charts.length, 2);
    expect(charts.last.series.last.points.single.value, 145);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'history filters by member and meal timing, with confirmed deletion updating Health',
    (t) async {
      store.addVital(sugar('fast', 99));
      store.addVital(
        sugar('post', 145, after: true, at: DateTime(2026, 11, 14, 14)),
      );
      store.addVital(sugar('dad', 200, member: 'father'));
      await mount(
        t,
        const ReadingHistoryScreen(memberId: 'son', type: VitalType.sugar),
      );
      expect(find.text('2 readings · newest first'), findsOneWidget);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('post'))).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('fast'))).dy),
      );
      expect(find.byKey(const ValueKey('dad')), findsNothing);
      await t.tap(find.text('Fasting'));
      await t.pumpAndSettle();
      expect(find.text('1 reading · newest first'), findsOneWidget);
      expect(find.byKey(const ValueKey('post')), findsNothing);
      await t.tap(find.byTooltip('Delete reading'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(store.healthReadingsOf('son', 'fbs'), hasLength(1));
      await t.tap(find.byTooltip('Delete reading'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(store.healthReadingsOf('son', 'fbs'), isEmpty);
      expect(find.text('No readings yet'), findsOneWidget);
      await t.ensureVisible(find.text('After meal'));
      await t.pumpAndSettle();
      await t.tap(find.text('After meal'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('post')), findsOneWidget);
      await t.tap(find.byType(MemberPicker));
      await t.pumpAndSettle();
      await t.tap(find.text('Father'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('post')), findsNothing);
      await t.ensureVisible(find.text('All sugar'));
      await t.pumpAndSettle();
      await t.tap(find.text('All sugar'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dad')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Health year filters include logs; BP, weight and oxygen need no conditions',
    (t) async {
      store.addVital(sugar('old', 99, at: DateTime(2024, 1, 2)));
      store.addVital(
        sugar('recent', 145, after: true, at: DateTime(2025, 1, 2)),
      );
      for (final (type, value) in [
        (VitalType.bp, 120.0),
        (VitalType.weight, 72.5),
        (VitalType.spo2, 98.0),
      ]) {
        store.addVital(
          Vital(
            id: type.name,
            memberId: 'son',
            type: type,
            at: DateTime(2025, 1, 2),
            a: value,
            b: type == VitalType.bp ? 80 : 0,
          ),
        );
      }
      await mount(t, const HealthScreen(), height: 2200);
      final cards = t.widgetList<TrendCard>(find.byType(TrendCard));
      expect(
        cards.map((c) => c.title),
        containsAll(['Blood pressure', 'Weight', 'Oxygen (SpO2)']),
      );
      await t.ensureVisible(find.text('2024'));
      await t.pumpAndSettle();
      await t.tap(find.text('2024'));
      await t.pumpAndSettle();
      final filtered = t.widgetList<TrendCard>(find.byType(TrendCard)).toList();
      expect(filtered, hasLength(1));
      expect(filtered.single.title, 'Fasting glucose');
      expect(filtered.single.points.single.date.year, 2024);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Today hands off the expanded member as adjacent headers pass mid-screen',
    (t) async {
      store.selectedId = null;
      for (final id in ['father', 'mother']) {
        store.addVital(sugar('$id-fasting', 99, member: id));
        store.addVital(sugar('$id-post', 145, member: id, after: true));
      }
      await mount(t, const TodayScreen(), width: 360, height: 640);
      final list = find.byType(ListView);
      Finder header(String name) => find.ancestor(
        of: find.descendant(of: list, matching: find.text(name)),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.expanded != null,
        ),
      );
      bool expanded(String name) =>
          t.widget<Semantics>(header(name)).properties.expanded!;
      Future<void> scrollPast(String name, double direction) async {
        final middle = t.getCenter(list).dy;
        final offset = t.getTopLeft(header(name)).dy - middle;
        await t.drag(list, Offset(0, -offset - direction * 28));
        await t.pumpAndSettle();
      }

      expect(expanded('Father'), isTrue);
      expect(expanded('Mother'), isFalse);
      await scrollPast('Mother', 1);
      expect(expanded('Mother'), isTrue);
      expect(expanded('Father'), isFalse);
      expect(find.text('Reading history'), findsOneWidget);
      await scrollPast('Father', -1);
      expect(expanded('Father'), isTrue);
      expect(expanded('Mother'), isFalse);
      await t.tap(header('Mother'));
      await t.pumpAndSettle();
      expect(expanded('Mother'), isTrue);
      expect(expanded('Father'), isFalse);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'the dock indicator slides and honors reduced motion',
    (t) async {
      Future<void> verify({required bool reducedMotion}) async {
        await mount(
          t,
          HomeShell(key: ValueKey(reducedMotion)),
          width: 360,
          height: 680,
          reducedMotion: reducedMotion,
        );
        final shell = find.descendant(
          of: find.byType(HomeShell),
          matching: find.byType(Scaffold),
        ).first;
        final dock = find.byWidget(t.widget<Scaffold>(shell).bottomNavigationBar!);
        final indicator = find.byType(AnimatedPositioned);
        double x() => t.getTopLeft(indicator).dx;
        final start = x();
        await t.tap(find.descendant(of: dock, matching: find.text('Health')));
        await t.pump();
        if (reducedMotion) {
          expect(x(), greaterThan(start));
          final end = x();
          await t.pumpAndSettle();
          expect(x(), end);
        } else {
          expect(x(), start);
          await t.pump(const Duration(milliseconds: 100));
          final middle = x();
          expect(middle, greaterThan(start));
          await t.pumpAndSettle();
          expect(x(), greaterThan(middle));
        }
      }

      await verify(reducedMotion: false);
      await verify(reducedMotion: true);
    },
  );

  testWidgets(
    'Today keeps update progress above the scrolling content',
    (t) async {
      final updates = _TestUpdateService()
        ..stage = UpdateStage.downloading
        ..progress = .42;
      addTearDown(updates.dispose);
      await mount(t, const TodayScreen(), height: 580, updates: updates);
      final card = find.byType(UpdateProgressCard);
      expect(find.text('42%'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(ListView), matching: card),
        findsNothing,
      );
      final position = t.getTopLeft(card);
      await t.drag(find.byType(ListView), const Offset(0, -120));
      await t.pumpAndSettle();
      expect(t.getTopLeft(card), position);
      updates.openingInstaller();
      await t.pumpAndSettle();
      expect(find.text('Opening Android installer…'), findsOneWidget);
    },
  );

  testWidgets(
    'fasting trends keep every point as results page on a narrow screen',
    (t) async {
      for (var i = 0; i < 27; i++) {
        store.addVital(
          sugar('trend$i', 90.0 + i, at: DateTime(2023 + i ~/ 9, 1 + i % 9)),
        );
      }
      await mount(
        t,
        const TestTrendScreen(memberId: 'son', testKey: 'fbs'),
        width: 320,
        height: 700,
        scale: 1.4,
        brightness: Brightness.dark,
      );
      final chart = find.byType(TrendChart);
      await t.tap(find.byTooltip('Timeline'));
      await t.pumpAndSettle();
      expect(find.text('1Y'), findsNothing);
      for (final year in ['2025', '2024', '2023']) {
        expect(find.text(year), findsOneWidget);
      }
      await t.tap(find.text('2024'));
      await t.pumpAndSettle();
      expect(find.text('2024'), findsOneWidget);
      await t.tap(find.byTooltip('Timeline'));
      await t.pumpAndSettle();
      await t.tap(find.text('All time'));
      await t.pumpAndSettle();
      expect(t.widget<TrendChart>(chart).series.single.points, hasLength(27));
      await t.tap(find.byTooltip('Zoom in'));
      await t.pumpAndSettle();
      final reset = find.widgetWithText(TextButton, 'Reset view');
      expect(t.widget<TextButton>(reset).onPressed, isNotNull);
      final next = find.text('Next');
      for (final range in ['11–20 of 27', '21–27 of 27']) {
        await t.scrollUntilVisible(next, 400, scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        await t.tap(next);
        await t.pumpAndSettle();
        expect(find.text(range), findsOneWidget);
      }
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
      scroll.position.jumpTo(0);
      await t.pumpAndSettle();
      expect(t.widget<TrendChart>(chart).series.single.points, hasLength(27));
      expect(t.widget<TextButton>(reset).onPressed, isNotNull);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'history reaches older readings and fits a small screen with large text',
    (t) async {
      for (var i = 0; i < 27; i++) {
        store.addVital(
          sugar('v$i', 90.0 + i, at: DateTime(2026, 11, 14, 8, i)),
        );
      }
      await mount(
        t,
        const ReadingHistoryScreen(memberId: 'son'),
        width: 360,
        height: 800,
        scale: 1.2,
      );
      expect(find.text('27 readings · newest first'), findsOneWidget);
      expect(find.text('1–10 of 27'), findsOneWidget);
      expect(find.byKey(const ValueKey('v26')), findsOneWidget);
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(find.text('11–20 of 27'), findsOneWidget);
      expect(find.byKey(const ValueKey('v16')), findsOneWidget);
      expect(find.byKey(const ValueKey('v26')), findsNothing);
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(find.text('21–27 of 27'), findsOneWidget);
      expect(find.byKey(const ValueKey('v6')), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('v0')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const ValueKey('v0')), findsOneWidget);
      await t.tap(find.text('Previous'));
      await t.pumpAndSettle();
      expect(find.text('11–20 of 27'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
