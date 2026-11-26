// Cult Smart Scale import and the Cult Fit dashboard.
//
// Screens are also rendered to build/shots/cult_*.png for eyeballing.
// To check a real report PDF end to end (pdfium from a Windows build):
//   $env:CULT_PDF="C:\path\Measurement_Report.pdf"; $env:PDFIUM_DLL="build\native_assets\windows\pdfium.dll"; flutter test test/cult_fit_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_health/core/theme.dart';
import 'package:family_health/data/cult_fit.dart';
import 'package:family_health/data/models.dart';
import 'package:family_health/data/reading_metric.dart';
import 'package:family_health/data/store.dart';
import 'package:family_health/services/importer.dart';
import 'package:family_health/ui/screens/cult_fit.dart';
import 'package:family_health/ui/screens/health.dart';
import 'package:family_health/ui/widgets/charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_data.dart';

/// The text layer of a Cult Smart Scale report as pdfium reads it, for a
/// fictional person.
String reportText({String date = '2026.11.6 09:00:24', double weight = 81.4, double fat = 22.6, double muscle = 59.1, double bmi = 25.4}) => '''
Measurement Report Ravi $date Male gender 30 age 179.0 cm height 79.5 HEALTH SCORE Body composition analysis
Weight-$weight *Total weight = water content + protein content + inorganic salt content + fat content
Total body water 42.1kg Protein mass 12.9kg Fat mass 18.4kg Others 8.0kg $weight weight(kg)
Weight management Parameter Measured Value Standard weight 70.5kg Weight control -10.9kg Fat control -6.2kg Muscle control 0 kg BMR 1790.0kcal
Fat Analysis Parameter Measured Value Fat Ratio $fat% Fat Mass 18.4kg Visceral fat 9.0
Bone & Muscle Mass Analysis Parameter Measured Value Weight(kg) 20 40 60 80 100 120 140 160 180 200 $weight(High)
Bone Mass(kg) 1 2 3 4 5 6 7 8 9 10 3.1(Standard) Muscle mass(kg) 15 30 45 60 75 90 105 120 135 150 $muscle(Excellent)
Skeletal Muscle mass(kg) 15 30 45 60 75 90 105 120 135 150 32.4(Standard)
Body Mass index Data (Normal range) Low Standard High BMI (kg/m²) (18.5 - 25.0) 12 14 16 18 19 20 21 24 29 36 43 $bmi
Body type Body fat percentage Lean Lean muscular Muscular Lack of exercise Standard Standard muscular Edematous obese Overweight muscular Muscular overweight
Muscle mass Muscle mass : insufficient standard excellent Body fat percentage: thin standard alert
Other indicators Parameter Measured Value Body age 32 Subcutaneous fat mass 12.6kg Health Evaluation Good Lean Body Mass 63.0kg
Disclaimer The Bluetooth body fat scale we sell is not a medical device. Cult Smart Scale''';

Future<void> _loadFonts() async {
  const root = 'C:/src/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String f) async => ByteData.sublistView(await File('$root/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('roboto-regular.ttf'))
    ..addFont(bytes('roboto-medium.ttf'))
    ..addFont(bytes('roboto-bold.ttf'));
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'))).load();
  // Colour emoji for the tab art (phones bring their own; Windows has Segoe UI Emoji).
  final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
  if (emoji.existsSync()) await (FontLoader('Emoji')..addFont(emoji.readAsBytes().then(ByteData.sublistView))).load();
}

void main() {
  late AppStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await AppStore.load();
    seedEmptyFamily(store);
    store.selectedId = 'son';
  });

  tearDown(() {
    store.saveNow();
    store.dispose();
  });

  group('report text', () {
    test('every field of a Cult Smart Scale report is read', () {
      final text = reportText();
      expect(CultMeasurement.recognizes(text), isTrue);
      final m = CultMeasurement.parse(text, 'Muscular overweight');
      expect(m.weight, 81.4);
      expect(m.fields['Scale profile'], 'Ravi');
      expect(m.fields['Health score'], 79.5);
      expect(m.fields['Fat ratio'], 22.6);
      expect(m.fields['Muscle control'], 0);
      expect(m.fields['Weight control'], -10.9);
      expect(m.fields['BMR'], 1790);
      expect(m.fields['Muscle mass'], 59.1);
      expect(m.fields['Muscle mass rating'], 'Excellent');
      expect(m.fields['Skeletal muscle mass'], 32.4);
      expect(m.fields['BMI'], 25.4);
      expect(m.fields['BMI reference range'], '18.5–25.0 kg/m²');
      expect(m.fields['Health evaluation'], 'Good');
      expect(m.fields['Body type'], 'Muscular overweight');
      // The scale prints India time; it is stored as the same instant.
      expect(m.at.toUtc(), DateTime.utc(2026, 11, 6, 3, 30, 24));
    });

    test('a lab report is not mistaken for a scale report', () {
      expect(CultMeasurement.recognizes('Vijaya Diagnostics\nHbA1c 6.1 %\nFasting blood sugar 104 mg/dL'), isFalse);
    });

    test('a broken layout is refused instead of half-read', () {
      expect(() => CultMeasurement.parse(reportText().replaceFirst('HEALTH SCORE', ''), 'Standard'), throwsFormatException);
    });
  });

  group('metrics', () {
    test('changes are signed, unit-aware and judged by direction', () {
      final fat = cultMetric('Fat ratio');
      expect(fat.withUnit(22.6), '22.6%');
      expect(fat.change(-1.24), '−1.2 pts');
      expect(fat.improved(-1.2), isTrue);
      expect(fat.improved(0.01), isNull); // rounds to no change
      final muscle = cultMetric('Muscle mass');
      expect(muscle.change(0.6), '+0.6 kg');
      expect(muscle.improved(-0.6), isFalse);
      expect(cultMetric('Total body water').improved(2), isNull);
      expect(cultMetric('Visceral fat').withUnit(9), '9');
      expect(cultMetric('BMR').withUnit(1790), '1790 kcal');
    });

    test('rating words', () {
      expect(cultRatingOk('Excellent'), isTrue);
      expect(cultRatingOk('High'), isFalse);
      expect(cultRatingOk('something new'), isNull);
    });
  });

  test('importing the same scan twice keeps one weight reading and no report', () async {
    final m = CultMeasurement.parse(reportText(), 'Standard');
    store.addCultMeasurement('son', m);
    store.addCultMeasurement('son', m);
    expect(store.vitals.single.a, 81.4);
    expect(store.vitals.single.type, VitalType.weight);
    expect(store.docs, isEmpty);
    store.saveNow();
    final restored = await AppStore.load();
    expect(restored.vitals.single.cultFit, m.fields);
    restored.dispose();
  });

  void seedScans() {
    final scans = [
      ('2026.5.4 08:10:00', 86.2, 25.8, 58.0, 26.9),
      ('2026.7.2 08:05:00', 84.0, 24.6, 58.4, 26.2),
      ('2026.9.1 08:20:00', 82.9, 23.5, 58.9, 25.9),
      ('2026.11.6 09:00:24', 81.4, 22.6, 59.1, 25.4),
    ];
    for (final (date, w, fat, muscle, bmi) in scans) {
      store.addCultMeasurement('son', CultMeasurement.parse(reportText(date: date, weight: w, fat: fat, muscle: muscle, bmi: bmi), 'Muscular overweight'));
    }
  }

  Future<void> pumpHealth(WidgetTester t, {Brightness brightness = Brightness.light, double width = 390, double height = 3400}) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness),
        home: const Scaffold(body: SafeArea(child: HealthScreen())),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Cult Fit data'));
    await t.pumpAndSettle();
  }

  testWidgets('the dashboard shows the latest scan, changes since the last one and trends', (t) async {
    seedScans();
    await pumpHealth(t);
    expect(find.text('Health score'), findsWidgets);
    expect(find.text('4 scans'), findsOneWidget);
    // Body fat went 23.5 → 22.6: shown as an improvement.
    expect(find.text('−0.9 pts'), findsOneWidget);
    expect(find.text('Body composition'), findsOneWidget);
    expect(find.text('Muscular overweight'), findsWidgets);
    // The trend explorer charts weight first, then follows the chosen metric.
    expect(t.widget<TrendChart>(find.byType(TrendChart)).series.single.points.map((p) => p.value), [86.2, 84.0, 82.9, 81.4]);
    await t.tap(find.widgetWithText(InkWell, 'Body fat').last);
    await t.pumpAndSettle();
    expect(t.widget<TrendChart>(find.byType(TrendChart)).series.single.points.last.value, 22.6);
    expect(t.takeException(), isNull);

    store.selectMember('mother');
    await t.pumpAndSettle();
    expect(find.text('No Cult Fit scans for Mother yet'), findsOneWidget);
  });

  testWidgets('a scan opens its full report and can be deleted', (t) async {
    seedScans();
    await pumpHealth(t);
    await t.tap(find.text('6 Nov 2026').last);
    await t.pumpAndSettle();
    expect(find.byType(CultScanScreen), findsOneWidget);
    expect(find.text('Weight management'), findsOneWidget);
    expect(find.text('1790 kcal'), findsOneWidget);
    await t.tap(find.text('Delete this scan'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(store.readingsFor('son', ReadingMetric.weight), hasLength(3));
    expect(find.text('3 scans'), findsOneWidget);
  });

  group('screenshots', () {
    final out = Directory('build/shots')..createSync(recursive: true);
    Future<void> shot(WidgetTester t, String name, Widget page, {bool dark = false, double h = 2900}) async {
      t.view.physicalSize = Size(390 * 2, h * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: () {
              final theme = buildTheme(dark ? Brightness.dark : Brightness.light);
              return theme.copyWith(textTheme: theme.textTheme.apply(fontFamilyFallback: ['Emoji']));
            }(),
            home: Scaffold(body: SafeArea(child: page)),
          ),
        ),
      ));
      await t.pumpAndSettle();
      if (page is HealthScreen) {
        await t.tap(find.text('Cult Fit data'));
        await t.pumpAndSettle();
      }
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    testWidgets('dashboard light, dark, empty and one scan', (t) async {
      await shot(t, 'cult_empty', const HealthScreen(), h: 844);
      seedScans();
      await shot(t, 'cult_dashboard', const HealthScreen());
      await shot(t, 'cult_dashboard_dark', const HealthScreen(), dark: true);
      final id = store.readingsFor('son', ReadingMetric.weight).last.id;
      await shot(t, 'cult_scan', CultScanScreen(vitalId: id), h: 1700);
    });
  });

  test('a real Cult Fit PDF is read end to end', () async {
    final path = Platform.environment['CULT_PDF'];
    Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_DLL'];
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('pdfrx').path;
    final r = await ImportService.read(File(path!).readAsBytesSync(), 'Measurement_Report.pdf');
    final cult = r.cult!;
    expect(cult.weight, greaterThan(0));
    for (final key in cultUnits.keys) {
      expect(cult.fields[key], isA<num>(), reason: key);
    }
    expect(cultBodyTypes.expand((row) => row), contains(cult.fields['Body type']));
  }, skip: Platform.environment['CULT_PDF'] == null ? 'Set CULT_PDF and PDFIUM_DLL to check a real report' : false);
}
