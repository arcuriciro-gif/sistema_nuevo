import 'package:flutter/material.dart';

/// Tokens visuales del shell (UI-only). Naranja / blanco / negro.
class AppTokens {
  AppTokens._();

  static const Color brandOrange = Color(0xFFFF7A00);
  static const Color ink = Color(0xFF0A0A0A);
  static const Color inkSoft = Color(0xFF171717);
  static const Color line = Color(0xFF2A2A2A);
  static const Color mute = Color(0xFF9CA3AF);
  static const Color muteSoft = Color(0xFF6B7280);

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double sidebarWidth = 248;
  static const double topBarHeight = 58;

  static Color shellBg(Brightness b) =>
      b == Brightness.dark ? ink : const Color(0xFF111111);

  static Color shellSurface(Brightness b) =>
      b == Brightness.dark ? inkSoft : const Color(0xFF1A1A1A);

  static Color shellBorder(Brightness b) =>
      b == Brightness.dark ? line : const Color(0xFF262626);

  static Color contentBg(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static const Color syncOk = Color(0xFF22C55E);
  static const Color syncWarn = Color(0xFFF59E0B);
  static const Color syncErr = Color(0xFFEF4444);
  static const Color syncOff = Color(0xFF9CA3AF);

  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF16A34A);
}
