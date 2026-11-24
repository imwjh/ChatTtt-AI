import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:Kelivo/theme/surface_ladder.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

// CJK/Latin fallback to stabilize fontWeight (w100-w600) on iOS for Chinese
const List<String> kDefaultFontFamilyFallback = <String>[
  'PingFang SC',
  'Heiti SC',
  'Hiragino Sans GB',
  'Roboto',
];

const List<String> kAndroidFontFamilyFallback = <String>['sans-serif'];

// Windows-specific font fallback to fix Chinese font rendering issues
const List<String> kWindowsFontFamilyFallback = <String>[
  'Twemoji Country Flags',
  'Segoe UI',
  'Microsoft YaHei',
  'SimHei',
];

// Get platform-appropriate font fallback list
List<String> getPlatformFontFallback() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return kAndroidFontFamilyFallback;
  }
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return kWindowsFontFamilyFallback;
  }
  return kDefaultFontFamilyFallback;
}

// Internal helper for theme building
List<String> _getPlatformFontFallback() => getPlatformFontFallback();

/// Derive page `surface` and `surfaceContainer*` from the palette.
///
/// Palette-declared `surface` is the card. Light page is that color sunk
/// 4 tones (skipped for pure-white background). Dark page is unchanged.
/// Container roles reuse [SurfaceLadder] so they stay on the same HCT ladder.
ColorScheme _applyPageSurface(
  ColorScheme scheme, {
  required bool pureBackground,
  bool layered = false,
}) {
  if (scheme.brightness == Brightness.dark) return scheme;
  if (pureBackground) {
    return scheme.copyWith(surface: const Color(0xFFFFFFFF));
  }
  if (!layered) return scheme;
  return scheme.copyWith(surface: shiftTone(scheme.surface, -4.0));
}

ColorScheme _withDerivedSurfaceContainers(
  ColorScheme s, {
  bool layered = false,
}) {
  final ladder = SurfaceLadder.fromScheme(s, layered: layered);
  return s.copyWith(
    surfaceContainerLowest: ladder.surfaceContainerLowest,
    surfaceContainerLow: ladder.surfaceContainerLow,
    surfaceContainer: ladder.surfaceContainer,
    surfaceContainerHigh: ladder.surfaceContainerHigh,
    surfaceContainerHighest: ladder.surfaceContainerHighest,
  );
}

DialogThemeData _dialogTheme(AppSemanticColors colors, ColorScheme scheme) {
  return DialogThemeData(
    backgroundColor: colors.overlaySurface(scheme),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  );
}

BottomSheetThemeData _bottomSheetTheme(
  AppSemanticColors colors,
  ColorScheme scheme,
) {
  return BottomSheetThemeData(
    backgroundColor: colors.overlaySurface(scheme),
    modalBackgroundColor: colors.overlaySurface(scheme),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    modalElevation: 0,
    dragHandleColor: scheme.onSurface.withValues(alpha: 0.35),
    dragHandleSize: const Size(32, 4),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
  );
}

InputDecorationThemeData _inputDecorationTheme(
  AppSemanticColors colors,
  ColorScheme scheme,
) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(22),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecorationThemeData(
    filled: true,
    fillColor: colors.surfaceFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    hintStyle: TextStyle(
      fontSize: 15,
      color: scheme.onSurface.withValues(alpha: 0.4),
    ),
    labelStyle: TextStyle(
      fontSize: 15,
      color: scheme.onSurface.withValues(alpha: 0.65),
    ),
    border: border(colors.hairline, 0.8),
    enabledBorder: border(colors.hairline, 0.8),
    focusedBorder: border(scheme.primary.withValues(alpha: 0.85), 1.2),
  );
}

PageTransitionsTheme _pageTransitionsTheme() {
  return const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
    },
  );
}

/// iOS 风格的外观收尾：更大的圆角、控件级输入框、iOS 转场动画。
ThemeData _applyIosChrome(
  ThemeData theme,
  AppSemanticColors colors,
  ColorScheme scheme,
) {
  RoundedRectangleBorder pill([double radius = 999]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  return theme.copyWith(
    dialogTheme: _dialogTheme(colors, scheme),
    bottomSheetTheme: _bottomSheetTheme(colors, scheme),
    inputDecorationTheme: _inputDecorationTheme(colors, scheme),
    pageTransitionsTheme: _pageTransitionsTheme(),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
  );
}

PopupMenuThemeData _popupMenuTheme(
  AppSemanticColors colors,
  ColorScheme scheme,
) {
  return PopupMenuThemeData(color: colors.overlaySurface(scheme));
}

TextTheme _withFontFallback(TextTheme base, List<String> fallback) {
  TextStyle? f(TextStyle? s) => s?.copyWith(fontFamilyFallback: fallback);
  return base.copyWith(
    displayLarge: f(base.displayLarge),
    displayMedium: f(base.displayMedium),
    displaySmall: f(base.displaySmall),
    headlineLarge: f(base.headlineLarge),
    headlineMedium: f(base.headlineMedium),
    headlineSmall: f(base.headlineSmall),
    titleLarge: f(base.titleLarge),
    titleMedium: f(base.titleMedium),
    titleSmall: f(base.titleSmall),
    bodyLarge: f(base.bodyLarge),
    bodyMedium: f(base.bodyMedium),
    bodySmall: f(base.bodySmall),
    labelLarge: f(base.labelLarge),
    labelMedium: f(base.labelMedium),
    labelSmall: f(base.labelSmall),
  );
}

// String _hex(Color c) => '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
// String _rgb(Color c) => 'r=${c.red}, g=${c.green}, b=${c.blue}, a=${(c.alpha / 255).toStringAsFixed(3)}';
// String _hsl(Color c) {
//   final hsl = HSLColor.fromColor(c);
//   return 'h=${hsl.hue.toStringAsFixed(1)} s=${(hsl.saturation * 100).toStringAsFixed(1)}% l=${(hsl.lightness * 100).toStringAsFixed(1)}%';
// }
// String _hsv(Color c) {
//   final hsv = HSVColor.fromColor(c);
//   return 'h=${hsv.hue.toStringAsFixed(1)} s=${(hsv.saturation * 100).toStringAsFixed(1)}% v=${(hsv.value * 100).toStringAsFixed(1)}%';
// }
// String _lum(Color c) => 'lum=${c.computeLuminance().toStringAsFixed(4)}';
//
// void _logOne(String tag, String name, Color c) {
//   debugPrint('[Theme/$tag][$name] ${_hex(c)} | ${_rgb(c)} | ${_hsl(c)} | ${_hsv(c)} | ${_lum(c)}');
// }
//
// void _logColorScheme(String tag, ColorScheme s) {
//   // Log a comprehensive dump of the scheme with HEX/RGB/HSL/HSV/Luminance.
//   debugPrint('[Theme/$tag] ================= ColorScheme Dump =================');
//   debugPrint('[Theme/$tag] brightness=${s.brightness}');
//   _logOne(tag, 'primary', s.primary);
//   _logOne(tag, 'onPrimary', s.onPrimary);
//   _logOne(tag, 'primaryContainer', s.primaryContainer);
//   _logOne(tag, 'onPrimaryContainer', s.onPrimaryContainer);
//   _logOne(tag, 'secondary', s.secondary);
//   _logOne(tag, 'onSecondary', s.onSecondary);
//   _logOne(tag, 'secondaryContainer', s.secondaryContainer);
//   _logOne(tag, 'onSecondaryContainer', s.onSecondaryContainer);
//   _logOne(tag, 'tertiary', s.tertiary);
//   _logOne(tag, 'onTertiary', s.onTertiary);
//   _logOne(tag, 'tertiaryContainer', s.tertiaryContainer);
//   _logOne(tag, 'onTertiaryContainer', s.onTertiaryContainer);
//   _logOne(tag, 'surface', s.surface);
//   _logOne(tag, 'onSurface', s.onSurface);
//   _logOne(tag, 'surfaceVariant', s.surfaceVariant);
//   _logOne(tag, 'onSurfaceVariant', s.onSurfaceVariant);
//   _logOne(tag, 'background', s.background);
//   _logOne(tag, 'onBackground', s.onBackground);
//   _logOne(tag, 'error', s.error);
//   _logOne(tag, 'onError', s.onError);
//   _logOne(tag, 'errorContainer', s.errorContainer);
//   _logOne(tag, 'onErrorContainer', s.onErrorContainer);
//   _logOne(tag, 'outline', s.outline);
//   _logOne(tag, 'outlineVariant', s.outlineVariant);
//   _logOne(tag, 'shadow', s.shadow);
//   _logOne(tag, 'scrim', s.scrim);
//   _logOne(tag, 'inverseSurface', s.inverseSurface);
//   _logOne(tag, 'onInverseSurface', s.onInverseSurface);
//   _logOne(tag, 'inversePrimary', s.inversePrimary);
//   _logOne(tag, 'surfaceTint', s.surfaceTint);
//   // Derived/common surfaces used in this app
//   _logOne(tag, 'cardBackground≈surface', s.surface);
//   _logOne(tag, 'scaffoldBackground', s.surface);
//   _logOne(tag, 'appBarBackground', s.surface);
//   // M3 tinted surfaces approximation at common elevations
//   final e1 = ElevationOverlay.applySurfaceTint(s.surface, s.surfaceTint, 1);
//   final e3 = ElevationOverlay.applySurfaceTint(s.surface, s.surfaceTint, 3);
//   final e6 = ElevationOverlay.applySurfaceTint(s.surface, s.surfaceTint, 6);
//   _logOne(tag, 'surface@1dp', e1);
//   _logOne(tag, 'surface@3dp', e3);
//   _logOne(tag, 'surface@6dp', e6);
//   debugPrint('[Theme/$tag] ======================================================');
// }

ThemeData buildLightTheme(ColorScheme? dynamicScheme) {
  final fontFallback = _getPlatformFontFallback();
  // ChatTtt：预览/独立页面也统一使用黑白灰调色板。
  final scheme = _withDerivedSurfaceContainers(
    _applyPageSurface(ThemePalettes.monochrome.light, pureBackground: false),
  );
  // _logColorScheme('Light ${dynamicScheme != null ? 'Dynamic' : 'Static'}', scheme);
  final colors = AppSemanticColors.light(scheme, layered: false);

  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[colors],
    dialogTheme: _dialogTheme(colors, scheme),
    bottomSheetTheme: _bottomSheetTheme(colors, scheme),
    popupMenuTheme: _popupMenuTheme(colors, scheme),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 14,
        fontWeight: AppFontWeights.medium,
        fontFamilyFallback: fontFallback,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionTextColor: scheme.primary,
      disabledActionTextColor: scheme.onInverseSurface.withValues(alpha: 0.5),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: AppFontWeights.semibold,
      ).copyWith(fontFamilyFallback: fontFallback),
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    ),
  );
  return _applyIosChrome(
    theme.copyWith(
      textTheme: _withFontFallback(theme.textTheme, fontFallback),
      primaryTextTheme: _withFontFallback(theme.primaryTextTheme, fontFallback),
    ),
    colors,
    scheme,
  );
}

// New: Build themes from a provided static palette (with optional dynamic override)
ThemeData buildLightThemeForScheme(
  ColorScheme staticScheme, {
  ColorScheme? dynamicScheme,
  bool pureBackground = false,
  bool layeredSurfaces = false,
}) {
  final fontFallback = _getPlatformFontFallback();
  var scheme = (dynamicScheme?.harmonized()) ?? staticScheme;
  if (pureBackground) {
    scheme = scheme.copyWith(
      inverseSurface: const Color(0xFF000000),
      onInverseSurface: const Color(0xFFFFFFFF),
    );
  }
  scheme = _withDerivedSurfaceContainers(
    _applyPageSurface(
      scheme,
      pureBackground: pureBackground,
      layered: layeredSurfaces,
    ),
    layered: layeredSurfaces,
  );
  // Align logging behavior with buildLightTheme so diagnostics are consistent.
  // _logColorScheme('Light ${dynamicScheme != null ? 'Dynamic' : 'Static'}', scheme);
  final colors = AppSemanticColors.light(scheme, layered: layeredSurfaces);
  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[colors],
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 14,
        fontWeight: AppFontWeights.medium,
        fontFamilyFallback: fontFallback,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionTextColor: scheme.primary,
      disabledActionTextColor: scheme.onInverseSurface.withValues(alpha: 0.5),
    ),
    dialogTheme: _dialogTheme(colors, scheme),
    bottomSheetTheme: _bottomSheetTheme(colors, scheme),
    popupMenuTheme: _popupMenuTheme(colors, scheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: AppFontWeights.semibold,
      ).copyWith(fontFamilyFallback: fontFallback),
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: scheme.surface,
      ),
    ),
  );
  return _applyIosChrome(
    theme.copyWith(
      textTheme: _withFontFallback(theme.textTheme, fontFallback),
      primaryTextTheme: _withFontFallback(theme.primaryTextTheme, fontFallback),
      canvasColor: scheme.surface,
    ),
    colors,
    scheme,
  );
}

ThemeData buildDarkTheme(ColorScheme? dynamicScheme) {
  final fontFallback = _getPlatformFontFallback();
  final scheme = _withDerivedSurfaceContainers(ThemePalettes.monochrome.dark);
  // _logColorScheme('Dark ${dynamicScheme != null ? 'Dynamic' : 'Static'}', scheme);
  final colors = AppSemanticColors.dark(scheme, layered: false);

  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[colors],
    dialogTheme: _dialogTheme(colors, scheme),
    bottomSheetTheme: _bottomSheetTheme(colors, scheme),
    popupMenuTheme: _popupMenuTheme(colors, scheme),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 14,
        fontWeight: AppFontWeights.medium,
        fontFamilyFallback: fontFallback,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionTextColor: scheme.primary,
      disabledActionTextColor: scheme.onInverseSurface.withValues(alpha: 0.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: AppFontWeights.semibold,
      ).copyWith(fontFamilyFallback: fontFallback),
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    ),
  );
  return _applyIosChrome(
    theme.copyWith(
      textTheme: _withFontFallback(theme.textTheme, fontFallback),
      primaryTextTheme: _withFontFallback(theme.primaryTextTheme, fontFallback),
    ),
    colors,
    scheme,
  );
}

ThemeData buildDarkThemeForScheme(
  ColorScheme staticScheme, {
  ColorScheme? dynamicScheme,
  bool pureBackground = false,
  bool layeredSurfaces = false,
}) {
  final fontFallback = _getPlatformFontFallback();
  var scheme = (dynamicScheme?.harmonized()) ?? staticScheme;
  if (pureBackground) {
    scheme = scheme.copyWith(
      surface: const Color(0xFF000000),
      inverseSurface: const Color(0xFFFFFFFF),
      onInverseSurface: const Color(0xFF000000),
    );
  }
  scheme = _withDerivedSurfaceContainers(scheme, layered: layeredSurfaces);
  // Align logging behavior with buildDarkTheme so diagnostics are consistent.
  // _logColorScheme('Dark ${dynamicScheme != null ? 'Dynamic' : 'Static'}', scheme);
  final colors = AppSemanticColors.dark(scheme, layered: layeredSurfaces);
  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[colors],
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 14,
        fontWeight: AppFontWeights.medium,
        fontFamilyFallback: fontFallback,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionTextColor: scheme.primary,
      disabledActionTextColor: scheme.onInverseSurface.withValues(alpha: 0.6),
    ),
    dialogTheme: _dialogTheme(colors, scheme),
    bottomSheetTheme: _bottomSheetTheme(colors, scheme),
    popupMenuTheme: _popupMenuTheme(colors, scheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: AppFontWeights.semibold,
      ).copyWith(fontFamilyFallback: fontFallback),
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: scheme.surface,
      ),
    ),
  );
  return _applyIosChrome(
    theme.copyWith(
      textTheme: _withFontFallback(theme.textTheme, fontFallback),
      primaryTextTheme: _withFontFallback(theme.primaryTextTheme, fontFallback),
      canvasColor: scheme.surface,
    ),
    colors,
    scheme,
  );
}
