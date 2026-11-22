import 'package:flutter/material.dart';

/// Paleta do PACE (opção B): verde-menta como cor principal e uma cor fixa
/// para cada medida (tempo = roxo, pace = laranja, calorias = rosa).
class PaceColors {
  static const mint = Color(0xFF12B886);
  static const mintDark = Color(0xFF0B7A57);
  static const mintBright = Color(0xFF3DDBA4);
  static const mintSoft = Color(0xFFE3F7EF);
  static const violet = Color(0xFF6D4AE0);
  static const orange = Color(0xFFD9580D);
  static const pink = Color(0xFFC2255C);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const bgLight = Color(0xFFF4F6F9);
  static const bgDark = Color(0xFF0B0F17);
  static const cardDark = Color(0xFF121826);
  static const lineDark = Color(0xFF1F2937);
  static const red = Color(0xFFE5484D);

  // Compatibilidade com nomes antigos.
  static const blue = mint;
  static const blueDark = mintDark;
  static const lime = mintBright;
  static const limeDark = mintDark;
  static const graphite = ink;
  static const grey = muted;
  static const surfaceDark = cardDark;
  static const teal = Color(0xFF0EA5A4);
}

/// Cores que mudam entre claro e escuro.
class Pal {
  final bool dark;
  const Pal(this.dark);

  static Pal of(BuildContext context) => Pal(Theme.of(context).brightness == Brightness.dark);

  Color get bg => dark ? PaceColors.bgDark : PaceColors.bgLight;
  Color get card => dark ? PaceColors.cardDark : Colors.white;
  Color get cardGlass => dark ? const Color(0xC7121826) : const Color(0xD1FFFFFF);
  Color get border => dark ? const Color(0x10FFFFFF) : const Color(0xFFEEF2F6);
  Color get ink => dark ? const Color(0xFFF1F5F9) : PaceColors.ink;
  Color get muted => dark ? const Color(0xFF94A3B8) : PaceColors.muted;
  Color get faint => dark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  Color get mint => dark ? PaceColors.mintBright : PaceColors.mint;
  Color get mintText => dark ? PaceColors.mintBright : PaceColors.mintDark;
  Color get mintSoft => dark ? const Color(0x1F3DDBA4) : PaceColors.mintSoft;
  Color get mintMid => dark ? const Color(0xFF1F5A47) : const Color(0xFFBDEBD9);
  Color get violet => dark ? const Color(0xFFA48BFF) : PaceColors.violet;
  Color get orange => dark ? const Color(0xFFFF9D5C) : PaceColors.orange;
  Color get pink => dark ? const Color(0xFFFF7AA8) : PaceColors.pink;
  Color get violetSoft => dark ? const Color(0x26A48BFF) : const Color(0xFFEEE9FE);
  Color get orangeSoft => dark ? const Color(0x26FF9D5C) : const Color(0xFFFFEEE3);
  Color get pinkSoft => dark ? const Color(0x26FF7AA8) : const Color(0xFFFDE8EF);
  Color get warnSoft => dark ? const Color(0x26F59E0B) : const Color(0xFFFFF4E5);
  Color get warn => dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  List<BoxShadow> get shadow => [
        BoxShadow(
          color: dark ? Colors.black.withValues(alpha: 0.35) : const Color(0x0F0F172A),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Números e títulos em Space Grotesk.
const kNumFont = 'SpaceGrotesk';

TextStyle numStyle(double size, {Color? color, FontWeight weight = FontWeight.w700, double? height}) => TextStyle(
      fontFamily: kNumFont,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size >= 28 ? -size * 0.03 : -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final pal = Pal(dark);
  final scheme = ColorScheme.fromSeed(seedColor: PaceColors.mint, brightness: b).copyWith(
    primary: pal.mint,
    onPrimary: dark ? PaceColors.bgDark : Colors.white,
    secondary: pal.mintText,
    onSecondary: Colors.white,
    tertiary: pal.violet,
    surface: pal.card,
    onSurface: pal.ink,
    onSurfaceVariant: pal.muted,
    error: PaceColors.red,
    outlineVariant: pal.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: pal.bg,
  );
  final text = base.textTheme.apply(bodyColor: pal.ink, displayColor: pal.ink);
  TextStyle? head(TextStyle? s) => s?.copyWith(fontFamily: kNumFont, fontWeight: FontWeight.w700, letterSpacing: -0.4);
  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: head(text.displaySmall),
      headlineLarge: head(text.headlineLarge),
      headlineMedium: head(text.headlineMedium),
      headlineSmall: head(text.headlineSmall),
      titleLarge: head(text.titleLarge),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: pal.bg,
      foregroundColor: pal.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: numStyle(22, color: pal.ink),
    ),
    cardTheme: CardThemeData(
      color: pal.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: pal.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pal.mint,
        foregroundColor: dark ? PaceColors.bgDark : Colors.white,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.ink,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: dark ? PaceColors.lineDark : const Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF161E2E) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: pal.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? PaceColors.lineDark : const Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: pal.mint, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: dark ? PaceColors.lineDark : const Color(0xFFE2E8F0)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? pal.mint : (dark ? PaceColors.lineDark : const Color(0xFFCBD5E1))),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: pal.border, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
