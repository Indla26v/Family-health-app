import 'package:family_health/core/theme.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/data/store.dart';
import 'package:family_health/ui/screens/diabetes_detail.dart';
import 'package:family_health/ui/screens/health.dart';
import 'package:family_health/ui/screens/log_reading.dart';
import 'package:family_health/ui/screens/reading_history.dart';
import 'package:family_health/ui/screens/test_trend.dart';
import 'package:family_health/ui/widgets/charts.dart';
import 'package:family_health/ui/widgets/common.dart';
import 'package:family_health/ui/widgets/trend_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_data.dart';

void main() {
  late AppStore store;

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
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: page),
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
        containsAll(['Fasting glucose (FBS)', 'Post-prandial glucose (PPBS)']),
      );
      expect(
        cards
            .firstWhere((c) => c.title == 'Fasting glucose (FBS)')
            .points
            .last
            .value,
        99,
      );
      expect(
        cards
            .firstWhere((c) => c.title == 'Post-prandial glucose (PPBS)')
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
      expect(filtered.single.title, 'Fasting glucose (FBS)');
      expect(filtered.single.points.single.date.year, 2024);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'history reaches older readings and fits a small screen with large text',
    (t) async {
      for (var i = 0; i < 25; i++) {
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
      expect(find.text('25 readings · newest first'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('v0')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const ValueKey('v0')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
