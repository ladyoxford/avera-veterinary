import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const _primaryBlue = Color(0xFF0B7DFF);
  static const _secondaryBlue = Color(0xFF21C8FF);
  static const _darkBackground = Color(0xFF101418);
  static const _darkCard = Color(0xFF171C22);
  static const _darkSurface = Color(0xFF1F2630);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primaryBlue,
      primary: _primaryBlue,
      secondary: _secondaryBlue,
      surface: const Color(0xFFFFFFFF),
      error: const Color(0xFFB42318),
    ).copyWith(
      onSurface: const Color(0xFF111827),
      onSurfaceVariant: const Color(0xFF4B5563),
      outline: const Color(0xFF9CA3AF),
      outlineVariant: const Color(0xFFD1D5DB),
    );
    return _build(
      scheme: scheme,
      scaffoldBackground: const Color(0xFFF5F8F6),
      cardColor: Colors.white,
      semantic: const AppSemanticColors(
        success: Color(0xFF198754),
        warning: Color(0xFFE5A100),
        danger: Color(0xFFB42318),
        info: Color(0xFF2374AB),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: _primaryBlue,
      primary: const Color(0xFF67B0FF),
      secondary: const Color(0xFF8CCBFF),
      surface: _darkSurface,
      error: const Color(0xFFFF8A80),
    ).copyWith(
      onSurface: const Color(0xFFFFFFFF),
      onSurfaceVariant: const Color(0xFFC2CAD4),
      outline: const Color(0xFF7B8794),
      outlineVariant: const Color(0xFF35404C),
    );
    return _build(
      scheme: scheme,
      scaffoldBackground: _darkBackground,
      cardColor: _darkCard,
      semantic: const AppSemanticColors(
        success: Color(0xFF6FD19A),
        warning: Color(0xFFFFC857),
        danger: Color(0xFFFF8A80),
        info: Color(0xFF7CC7F2),
      ),
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color cardColor,
    required AppSemanticColors semantic,
  }) {
    final baseText = GoogleFonts.interTextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: const ['Roboto'],
    );
    final textTheme = baseText.copyWith(
      displayLarge: GoogleFonts.sora(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      displayMedium: GoogleFonts.sora(
        fontSize: 32,
        height: 1.18,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      displaySmall: GoogleFonts.sora(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineLarge: GoogleFonts.sora(
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineMedium: GoogleFonts.sora(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineSmall: GoogleFonts.sora(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 17,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: .35,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardColor,
      textTheme: textTheme,
      extensions: [semantic],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBackground,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: cardColor,
        shadowColor: Colors.black.withValues(alpha: .08),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cardColor,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .35),
        labelStyle: textTheme.labelMedium,
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: scheme.primary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.labelMedium?.copyWith(color: scheme.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        extendedTextStyle: textTheme.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
        unselectedLabelStyle: textTheme.labelMedium?.copyWith(fontSize: 14),
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        labelStyle: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        secondaryLabelStyle: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
