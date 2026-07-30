import 'package:flutter/material.dart';

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

/// The single semantic typography contract for product UI. Branding and
/// specialist data visualisations may opt out, but standard screens should not.
class AveraTextStyles extends ThemeExtension<AveraTextStyles> {
  const AveraTextStyles({
    required this.pageTitle,
    required this.pageSubtitle,
    required this.sectionTitle,
    required this.sectionSubtitle,
    required this.sectionLabel,
    required this.fieldValue,
    required this.fieldPlaceholder,
    required this.listItemTitle,
    required this.listItemSubtitle,
    required this.buttonLabel,
    required this.caption,
  });

  final TextStyle pageTitle;
  final TextStyle pageSubtitle;
  final TextStyle sectionTitle;
  final TextStyle sectionSubtitle;
  final TextStyle sectionLabel;
  final TextStyle fieldValue;
  final TextStyle fieldPlaceholder;
  final TextStyle listItemTitle;
  final TextStyle listItemSubtitle;
  final TextStyle buttonLabel;
  final TextStyle caption;

  @override
  AveraTextStyles copyWith({
    TextStyle? pageTitle,
    TextStyle? pageSubtitle,
    TextStyle? sectionTitle,
    TextStyle? sectionSubtitle,
    TextStyle? sectionLabel,
    TextStyle? fieldValue,
    TextStyle? fieldPlaceholder,
    TextStyle? listItemTitle,
    TextStyle? listItemSubtitle,
    TextStyle? buttonLabel,
    TextStyle? caption,
  }) => AveraTextStyles(
    pageTitle: pageTitle ?? this.pageTitle,
    pageSubtitle: pageSubtitle ?? this.pageSubtitle,
    sectionTitle: sectionTitle ?? this.sectionTitle,
    sectionSubtitle: sectionSubtitle ?? this.sectionSubtitle,
    sectionLabel: sectionLabel ?? this.sectionLabel,
    fieldValue: fieldValue ?? this.fieldValue,
    fieldPlaceholder: fieldPlaceholder ?? this.fieldPlaceholder,
    listItemTitle: listItemTitle ?? this.listItemTitle,
    listItemSubtitle: listItemSubtitle ?? this.listItemSubtitle,
    buttonLabel: buttonLabel ?? this.buttonLabel,
    caption: caption ?? this.caption,
  );

  @override
  AveraTextStyles lerp(AveraTextStyles? other, double t) {
    if (other is! AveraTextStyles) return this;
    return AveraTextStyles(
      pageTitle: TextStyle.lerp(pageTitle, other.pageTitle, t)!,
      pageSubtitle: TextStyle.lerp(pageSubtitle, other.pageSubtitle, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      sectionSubtitle: TextStyle.lerp(
        sectionSubtitle,
        other.sectionSubtitle,
        t,
      )!,
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
      fieldValue: TextStyle.lerp(fieldValue, other.fieldValue, t)!,
      fieldPlaceholder: TextStyle.lerp(
        fieldPlaceholder,
        other.fieldPlaceholder,
        t,
      )!,
      listItemTitle: TextStyle.lerp(listItemTitle, other.listItemTitle, t)!,
      listItemSubtitle: TextStyle.lerp(
        listItemSubtitle,
        other.listItemSubtitle,
        t,
      )!,
      buttonLabel: TextStyle.lerp(buttonLabel, other.buttonLabel, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
    );
  }
}

class AveraSpacing {
  const AveraSpacing._();
  static const pageHorizontalPadding = 20.0;
  static const pageTopPadding = 20.0;
  static const titleToSubtitleGap = 6.0;
  static const subtitleToContentGap = 24.0;
  static const sectionGap = 28.0;
  static const cardGap = 16.0;
  static const compactRowGap = 12.0;
  static const cardRadius = 16.0;
  static const cardPadding = 16.0;
  static const largeCardPadding = 20.0;
  static const minimumTapTarget = 48.0;
  static const bottomContentClearance = 152.0;
}

class AppTheme {
  const AppTheme._();

  static const primary = Color(0xFF087F7B);
  static const secondary = Color(0xFF2563EB);
  static const accent = Color(0xFFE76F51);
  static const success = Color(0xFF168A5B);
  static const warning = Color(0xFFD89A18);
  static const error = Color(0xFFD64550);
  static const lightSurface = Color(0xFFF5F7F9);
  static const darkSurface = Color(0xFF171C22);

  static const _darkBackground = Color(0xFF101418);
  static const _darkCard = Color(0xFF1F2630);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: secondary,
          tertiary: accent,
          surface: lightSurface,
          error: error,
        ).copyWith(
          onPrimary: Colors.white,
          onSurface: const Color(0xFF111827),
          onSurfaceVariant: const Color(0xFF4B5563),
          outline: const Color(0xFF9CA3AF),
          outlineVariant: const Color(0xFFD1D5DB),
        );
    return _build(
      scheme: scheme,
      scaffoldBackground: lightSurface,
      cardColor: Colors.white,
      semantic: const AppSemanticColors(
        success: success,
        warning: warning,
        danger: error,
        info: secondary,
      ),
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: primary,
          primary: primary,
          secondary: secondary,
          tertiary: accent,
          surface: darkSurface,
          error: error,
        ).copyWith(
          onPrimary: Colors.white,
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
        success: success,
        warning: warning,
        danger: error,
        info: secondary,
      ),
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color cardColor,
    required AppSemanticColors semantic,
  }) {
    final baseText =
        ThemeData(
          brightness: scheme.brightness,
          fontFamily: 'Inter',
        ).textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamilyFallback: const ['Roboto'],
        );
    final textTheme = baseText.copyWith(
      displayLarge: TextStyle(
        fontFamily: 'Sora',
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Sora',
        fontSize: 32,
        height: 1.18,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Sora',
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Sora',
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Sora',
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Sora',
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: .35,
        color: scheme.onSurfaceVariant,
      ),
    );

    final averaText = AveraTextStyles(
      pageTitle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      pageSubtitle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      sectionTitle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      sectionSubtitle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      sectionLabel: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
        color: scheme.primary,
      ),
      fieldValue: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      fieldPlaceholder: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      listItemTitle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      listItemSubtitle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      buttonLabel: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: scheme.onPrimary,
      ),
      caption: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardColor,
      textTheme: textTheme,
      extensions: [semantic, averaText],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBackground,
        foregroundColor: scheme.onSurface,
        titleTextStyle: averaText.pageTitle,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: cardColor,
        shadowColor: Colors.black.withValues(alpha: .08),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
        ),
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
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.primary,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          ),
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
        secondaryLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
