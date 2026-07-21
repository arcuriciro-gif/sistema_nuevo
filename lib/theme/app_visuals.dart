import 'package:flutter/material.dart';

class AppVisuals {
  static Color primaryAccent(ColorScheme scheme) => scheme.primary;

  static Color secondaryAccent(ColorScheme scheme) => scheme.secondary;

  static Color tertiaryAccent(ColorScheme scheme) => scheme.tertiary;

  static Color success(ColorScheme scheme) =>
      Color.lerp(scheme.primary, const Color(0xFF16A34A), 0.35)!;

  static Color warning(ColorScheme scheme) =>
      Color.lerp(scheme.primary, const Color(0xFFF59E0B), 0.45)!;

  static Color danger(ColorScheme scheme) =>
      Color.lerp(scheme.error, const Color(0xFFEF4444), 0.15)!;

  static Color info(ColorScheme scheme) =>
      Color.lerp(scheme.primary, scheme.secondary, 0.55)!;

  static Color neutral(ColorScheme scheme) => scheme.outline;
}
