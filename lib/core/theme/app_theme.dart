import 'dart:ui';

import 'package:flutter/material.dart';

/// Theme mode preference
enum AppThemeMode {
  light,
  dark,
  system,
}

/// Application theme configuration with Material 3 + macOS Liquid Glass aesthetic.
///
/// Inspired by macOS 26.5.x "Liquid Glass" design language:
/// - Translucent layered surfaces
/// - Deep backdrop blur
/// - Subtle vibrancy effects
/// - Refined typography with system-matching hierarchy
class AppTheme {
  AppTheme._();

  // ─── Brand Colors ───────────────────────────────────────────────

  static const Color _lightSeed = Color(0xFF0066FF); // vibrant macOS blue
  static const Color _darkSeed = Color(0xFF409CFF); // accessible on dark

  // ─── Light Theme ────────────────────────────────────────────────

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _lightSeed,
          brightness: Brightness.light,
          surface: const Color(0xFFF2F2F7),
          onSurface: const Color(0xFF1D1D1F),
          surfaceContainerHighest: const Color(0xFFE5E5EA),
          outline: const Color(0xFFD1D1D6),
        ),
        scaffoldBackgroundColor: const Color(0xFFECECF0),
        canvasColor: const Color(0xFFF2F2F7),
        dividerColor: const Color(0x25000000),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'SF Pro',
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1D1D1F),
            letterSpacing: -0.2,
          ),
          iconTheme: IconThemeData(color: Color(0xFF1D1D1F)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x20000000), width: 0.5),
          ),
          color: const Color(0xF0FFFFFF),
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x15000000),
        ),
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          minVerticalPadding: 4,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xF0FFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x20000000), width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x20000000), width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _lightSeed, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0x18000000),
          thickness: 0.5,
          space: 1,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.all(6),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            elevation: 0,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: const Color(0xF01D1D1F),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
          elevation: 8,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xF01D1D1F),
            borderRadius: BorderRadius.circular(7),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          waitDuration: const Duration(milliseconds: 400),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: WidgetStateProperty.all(true),
          interactive: true,
          thickness: WidgetStateProperty.all(8),
          radius: const Radius.circular(4),
          thumbColor: WidgetStateProperty.all(const Color(0x60000000)),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xF5FFFFFF),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x15000000), width: 0.5),
          ),
          textStyle: const TextStyle(fontSize: 13, color: Color(0xFF1D1D1F)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xF8FFFFFF),
          elevation: 16,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x15000000), width: 0.5),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1D1D1F),
          ),
        ),
      );

  // ─── Dark Theme ─────────────────────────────────────────────────

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _darkSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF1C1C1E),
          onSurface: const Color(0xFFF5F5F7),
          surfaceContainerHighest: const Color(0xFF2C2C2E),
          outline: const Color(0xFF3A3A3C),
        ),
        scaffoldBackgroundColor: const Color(0xFF141416),
        canvasColor: const Color(0xFF1C1C1E),
        dividerColor: const Color(0x25FFFFFF),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'SF Pro',
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF5F5F7),
            letterSpacing: -0.2,
          ),
          iconTheme: IconThemeData(color: Color(0xFFF5F5F7)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x25FFFFFF), width: 0.5),
          ),
          color: const Color(0xE02C2C2E),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black38,
        ),
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          minVerticalPadding: 4,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xE02C2C2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x25FFFFFF), width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x25FFFFFF), width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _darkSeed, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0x22FFFFFF),
          thickness: 0.5,
          space: 1,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.all(6),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            elevation: 0,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: const Color(0xF0F5F5F7),
          contentTextStyle: const TextStyle(color: Color(0xFF1D1D1F), fontSize: 13),
          elevation: 8,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xF02C2C2E),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0x30FFFFFF), width: 0.5),
          ),
          textStyle: const TextStyle(color: Color(0xFFF5F5F7), fontSize: 11.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          waitDuration: const Duration(milliseconds: 400),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: WidgetStateProperty.all(true),
          interactive: true,
          thickness: WidgetStateProperty.all(8),
          radius: const Radius.circular(4),
          thumbColor: WidgetStateProperty.all(const Color(0x60FFFFFF)),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xF02C2C2E),
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x30FFFFFF), width: 0.5),
          ),
          textStyle: const TextStyle(fontSize: 13, color: Color(0xFFF5F5F7)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xF02C2C2E),
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x30FFFFFF), width: 0.5),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF5F5F7),
          ),
        ),
      );

  // ─── Glass Effect Helpers ───────────────────────────────────────

  /// Blur sigma for glass effect (Liquid Glass: stronger blur)
  static const double glassBlurSigma = 28.0;

  /// Glass effect color for light mode — more transparent for layered look
  static const Color glassLight = Color(0xC8FFFFFF);

  /// Glass effect color for dark mode
  static const Color glassDark = Color(0xC81C1C1E);

  /// Border color for glass surfaces in light mode
  static const Color glassBorderLight = Color(0x28000000);

  /// Border color for glass surfaces in dark mode
  static const Color glassBorderDark = Color(0x30FFFFFF);

  /// Get the appropriate glass color for the given brightness
  static Color glassColor(Brightness brightness) =>
      brightness == Brightness.light ? glassLight : glassDark;

  /// Get the appropriate glass border color for the given brightness
  static Color glassBorderColor(Brightness brightness) =>
      brightness == Brightness.light ? glassBorderLight : glassBorderDark;

  /// Create a glass blur filter
  static ImageFilter glassFilter({double? sigma}) =>
      ImageFilter.blur(sigmaX: sigma ?? glassBlurSigma, sigmaY: sigma ?? glassBlurSigma);

  // ─── Liquid Glass surface gradients ────────────────────────────

  /// Subtle shimmer gradient for glass cards/panels in light mode
  static const Gradient glassGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xF8FFFFFF), Color(0xECF5F5F7)],
  );

  /// Subtle shimmer gradient for glass cards/panels in dark mode
  static const Gradient glassGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xE82C2C2E), Color(0xE01C1C1E)],
  );

  static Gradient glassGradient(Brightness brightness) =>
      brightness == Brightness.light ? glassGradientLight : glassGradientDark;
}