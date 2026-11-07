import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../ui/widgets/motion.dart';

/// Design tokens, taken from the approved artboards (light) and the brief's
/// dark-mode notes. Use `context.c` everywhere instead of raw colours.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.accent2,
    required this.accentTint,
    required this.onAccent,
    required this.ok,
    required this.okTint,
    required this.warn,
    required this.warnTint,
    required this.danger,
    required this.dangerTint,
    required this.info,
    required this.infoTint,
    required this.shadow,
  });

  final Color bg, surface, surfaceAlt, border, text, textSecondary;

  /// Teal brand colour; [accent2] (indigo) is its partner in gradients and charts.
  final Color accent, accent2, accentTint, onAccent;
  final Color ok, okTint, warn, warnTint, danger, dangerTint, info, infoTint;
  final Color shadow;

  /// [color] laid lightly over the card surface: coloured card backgrounds.
  Color tint(Color color, [double amount = .08]) => Color.alphaBlend(color.withValues(alpha: amount), surface);

  /// Soft teal → indigo wash for highlighted cards.
  LinearGradient get softGradient => LinearGradient(colors: [tint(accent, .12), tint(accent2, .12)], begin: Alignment.topLeft, end: Alignment.bottomRight);

  /// Primary buttons, the add button and hero cards.
  LinearGradient get gradient => LinearGradient(colors: [accent, accent2], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static const light = AppPalette(
    bg: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF2F8),
    border: Color(0xFFE4E9F2),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF5A6A82),
    accent: Color(0xFF0F766E),
    accent2: Color(0xFF4F46E5),
    accentTint: Color(0x2414B8A6),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF047857),
    okTint: Color(0x2410B981),
    warn: Color(0xFFB45309),
    warnTint: Color(0x29F59E0B),
    danger: Color(0xFFE11D48),
    dangerTint: Color(0x1FF43F5E),
    info: Color(0xFF4F46E5),
    infoTint: Color(0x1F6366F1),
    shadow: Color(0x0F1E3A66),
  );

  static const dark = AppPalette(
    bg: Color(0xFF090E1A),
    surface: Color(0xFF131B2D),
    surfaceAlt: Color(0xFF1C2740),
    border: Color(0xFF27344F),
    text: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF9AA8BF),
    accent: Color(0xFF2DD4BF),
    accent2: Color(0xFF818CF8),
    accentTint: Color(0x2E2DD4BF),
    onAccent: Color(0xFF042F2C),
    ok: Color(0xFF34D399),
    okTint: Color(0x2E10B981),
    warn: Color(0xFFFBBF24),
    warnTint: Color(0x2EF59E0B),
    danger: Color(0xFFFB7185),
    dangerTint: Color(0x2EF43F5E),
    info: Color(0xFFA5B4FC),
    infoTint: Color(0x2E6366F1),
    shadow: Color(0x47000000),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

extension PaletteX on BuildContext {
  AppPalette get c => Theme.of(this).extension<AppPalette>()!;
}

/// Type scale from the brief (sp values; Large-text mode scales everything x1.2
/// through the app-wide text scaler).
class AppText {
  static const displayNumber = TextStyle(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);
  static const numberLarge = TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]);
  static const titleLarge = TextStyle(fontSize: 19, height: 26 / 19, fontWeight: FontWeight.w600);
  static const title = TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 16, height: 23 / 16, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500);
  static const caption = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
}

const kRadiusCard = 22.0;
const kRadiusInput = 14.0;
const kSide = 16.0;

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.light ? AppPalette.light : AppPalette.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: b).copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      surface: p.surface,
      onSurface: p.text,
      outline: p.border,
      error: p.danger,
    ),
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.border,
    extensions: [p],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeSlidePageTransitionsBuilder(),
    }),
    splashFactory: InkSparkle.splashFactory,
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    popupMenuTheme: PopupMenuThemeData(color: p.surface, surfaceTintColor: Colors.transparent, elevation: 8, shadowColor: p.shadow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, circularTrackColor: p.accentTint),
    switchTheme: SwitchThemeData(trackOutlineColor: WidgetStateProperty.all(Colors.transparent)),
    appBarTheme: AppBarTheme(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, scrolledUnderElevation: 0),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.text,
      contentTextStyle: TextStyle(color: p.bg, fontSize: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusInput), borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusInput), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusInput), borderSide: BorderSide(color: p.accent, width: 2)),
    ),
  );
}

/// Member colours (avatar ring + chart series), as drawn on the artboards.
class MemberColors {
  static const father = Color(0xFF7C3AED);
  static const mother = Color(0xFFF97316);
  static const daughter = Color(0xFF0EA5E9);
  static const son = Color(0xFF14B8A6);
  static const all = Color(0xFF4F46E5);
}
