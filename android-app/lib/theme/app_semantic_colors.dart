import 'package:flutter/material.dart';
import 'package:Kelivo/theme/surface_ladder.dart';

/// Semantic colors that have no dedicated role in [ColorScheme].
///
/// All values are derived from (or harmonized with) the active [ColorScheme]
/// so custom/seed-generated themes get sensible values automatically.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color surfaceFill;
  final Color surfaceCard;
  final Color surfaceCardFill;
  final Color hairline;
  final Color hairlineStrong;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color searchHighlight;
  final List<Color> chartSeries;
  final bool layered;

  const AppSemanticColors({
    required this.surfaceFill,
    required this.surfaceCard,
    required this.surfaceCardFill,
    required this.hairline,
    required this.hairlineStrong,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.searchHighlight,
    required this.chartSeries,
    this.layered = false,
  });

  /// Dialog / sheet / menu panel fill.
  ///
  /// Layered mode sits on the bright card layer. Legacy uses page
  /// [ColorScheme.surface] so overlays match the old look.
  Color overlaySurface(ColorScheme scheme) =>
      layered ? surfaceCard : scheme.surface;

  factory AppSemanticColors.light(ColorScheme cs, {bool layered = false}) {
    final ladder = SurfaceLadder.fromScheme(cs, layered: layered);
    return AppSemanticColors(
      surfaceFill: ladder.surfaceFill,
      surfaceCard: ladder.card,
      surfaceCardFill: ladder.surfaceCardFill,
      hairline: ladder.hairline,
      hairlineStrong: ladder.hairlineStrong,
      // ChatTtt：语义色也只使用黑白灰，避免界面出现彩色点缀。
      success: const Color(0xFF1F1F1F),
      successContainer: const Color(0xFFE8E8E8),
      onSuccessContainer: const Color(0xFF0A0A0A),
      warning: const Color(0xFF5C5C5C),
      warningContainer: const Color(0xFFEDEDED),
      onWarningContainer: const Color(0xFF141414),
      searchHighlight: const Color(0x1F000000),
      layered: layered,
      chartSeries: const [
        Color(0xFF111111),
        Color(0xFF2E2E2E),
        Color(0xFF4A4A4A),
        Color(0xFF666666),
        Color(0xFF808080),
        Color(0xFF9A9A9A),
        Color(0xFFB5B5B5),
        Color(0xFFD0D0D0),
      ],
    );
  }

  factory AppSemanticColors.dark(ColorScheme cs, {bool layered = false}) {
    final ladder = SurfaceLadder.fromScheme(cs, layered: layered);
    return AppSemanticColors(
      surfaceFill: ladder.surfaceFill,
      surfaceCard: ladder.card,
      surfaceCardFill: ladder.surfaceCardFill,
      hairline: ladder.hairline,
      hairlineStrong: ladder.hairlineStrong,
      success: const Color(0xFFE0E0E0),
      successContainer: const Color(0xFF2C2C2C),
      onSuccessContainer: const Color(0xFFF5F5F5),
      warning: const Color(0xFFB0B0B0),
      warningContainer: const Color(0xFF333333),
      onWarningContainer: const Color(0xFFF0F0F0),
      searchHighlight: const Color(0x2EFFFFFF),
      layered: layered,
      chartSeries: const [
        Color(0xFFF5F5F5),
        Color(0xFFD8D8D8),
        Color(0xFFBBBBBB),
        Color(0xFF9E9E9E),
        Color(0xFF818181),
        Color(0xFF666666),
        Color(0xFF4C4C4C),
        Color(0xFF333333),
      ],
    );
  }

  @override
  AppSemanticColors copyWith({
    Color? surfaceFill,
    Color? surfaceCard,
    Color? surfaceCardFill,
    Color? hairline,
    Color? hairlineStrong,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? searchHighlight,
    List<Color>? chartSeries,
    bool? layered,
  }) {
    return AppSemanticColors(
      surfaceFill: surfaceFill ?? this.surfaceFill,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceCardFill: surfaceCardFill ?? this.surfaceCardFill,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      searchHighlight: searchHighlight ?? this.searchHighlight,
      chartSeries: chartSeries ?? this.chartSeries,
      layered: layered ?? this.layered,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    final len = chartSeries.length < other.chartSeries.length
        ? chartSeries.length
        : other.chartSeries.length;
    return AppSemanticColors(
      surfaceFill: Color.lerp(surfaceFill, other.surfaceFill, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceCardFill: Color.lerp(surfaceCardFill, other.surfaceCardFill, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      searchHighlight: Color.lerp(searchHighlight, other.searchHighlight, t)!,
      chartSeries: List.generate(
        len,
        (i) => Color.lerp(chartSeries[i], other.chartSeries[i], t)!,
      ),
      layered: t < 0.5 ? layered : other.layered,
    );
  }
}

/// Inline surface overrides intentionally do not extend InheritedTheme.
/// Dialogs, menus and routes capture the ordinary theme, not pane materials.
class AppSurfaceColorsScope extends InheritedWidget {
  const AppSurfaceColorsScope({
    super.key,
    required this.colors,
    required super.child,
  });

  final AppSemanticColors colors;

  @override
  bool updateShouldNotify(AppSurfaceColorsScope oldWidget) =>
      colors != oldWidget.colors;
}

extension AppSemanticColorsX on BuildContext {
  /// The ambient [AppSemanticColors]. Falls back to deriving values from the
  /// ambient [ColorScheme] when the extension is not attached (e.g. in widget
  /// tests that pump a plain MaterialApp).
  AppSemanticColors get appColors {
    final scoped = dependOnInheritedWidgetOfExactType<AppSurfaceColorsScope>();
    if (scoped != null) return scoped.colors;
    return _themeColors;
  }

  AppSemanticColors get _themeColors {
    final theme = Theme.of(this);
    final ext = theme.extension<AppSemanticColors>();
    if (ext != null) return ext;
    return theme.brightness == Brightness.dark
        ? AppSemanticColors.dark(theme.colorScheme)
        : AppSemanticColors.light(theme.colorScheme);
  }

  /// Dialog / sheet / menu panel. See [AppSemanticColors.overlaySurface].
  /// Callers may resolve this before opening a route, from inside a pane.
  Color get overlaySurface =>
      _themeColors.overlaySurface(Theme.of(this).colorScheme);
}
