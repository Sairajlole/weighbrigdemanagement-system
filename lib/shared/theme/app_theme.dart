import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _seed = Color(0xFF059669);
  static const defaultAccent = Color(0xFF059669);
  static const successColor = Color(0xFF059669);
  static const proColor = Color(0xFF7C3AED);
  static const proGradient = [Color(0xFF7C3AED), Color(0xFF4F46E5)];

  static ThemeData lightFrom({Color? seed}) {
    return _build(seed ?? _seed, Brightness.light);
  }

  static ThemeData darkFrom({Color? seed}) {
    return _build(seed ?? _seed, Brightness.dark);
  }

  static ThemeData get light => lightFrom();
  static ThemeData get dark => darkFrom();

  static ThemeData _build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final fontFamily = GoogleFonts.ibmPlexSans().fontFamily;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          inherit: true,
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: scheme.surface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(inherit: true, fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(inherit: true, fontFamily: fontFamily, fontSize: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        labelStyle: TextStyle(inherit: true, fontFamily: fontFamily, fontSize: 14, color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide.none,
        labelStyle: TextStyle(inherit: true, fontFamily: fontFamily, fontSize: 11),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(scheme.surfaceContainerLow),
        headingTextStyle: TextStyle(inherit: true, fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        dataTextStyle: TextStyle(inherit: true, fontFamily: fontFamily, fontSize: 12, color: scheme.onSurface),
        dividerThickness: 0.5,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
