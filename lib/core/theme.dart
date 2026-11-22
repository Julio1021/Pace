import 'package:flutter/material.dart';

/// Paleta do PACE: azul elétrico (primária), verde-lima (progresso),
/// grafite (texto) e cinza neutro (texto secundário).
class PaceColors {
  static const blue = Color(0xFF1F5BFF);
  static const blueDark = Color(0xFF0B2E99);
  static const lime = Color(0xFFA6E22E);
  static const limeDark = Color(0xFF5E8C00);
  static const graphite = Color(0xFF1C2230);
  static const grey = Color(0xFF6B7385);
  static const bgLight = Color(0xFFF4F6FA);
  static const bgDark = Color(0xFF0E1117);
  static const surfaceDark = Color(0xFF171B24);
  static const orange = Color(0xFFFF8A3D);
  static const red = Color(0xFFE5484D);
  static const teal = Color(0xFF14B8A6);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: PaceColors.blue,
    brightness: b,
  ).copyWith(
    primary: dark ? const Color(0xFF6E95FF) : PaceColors.blue,
    onPrimary: Colors.white,
    secondary: dark ? PaceColors.lime : PaceColors.limeDark,
    onSecondary: dark ? PaceColors.graphite : Colors.white,
    tertiary: PaceColors.lime,
    surface: dark ? PaceColors.surfaceDark : Colors.white,
    onSurface: dark ? const Color(0xFFE8EAF0) : PaceColors.graphite,
    onSurfaceVariant: dark ? const Color(0xFF9AA2B4) : PaceColors.grey,
    error: PaceColors.red,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: dark ? PaceColors.bgDark : PaceColors.bgLight,
  );
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? PaceColors.bgDark : PaceColors.bgLight,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      height: 68,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1F2430) : const Color(0xFFF0F2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.onSurface.withValues(alpha: 0.08), space: 1),
  );
}
