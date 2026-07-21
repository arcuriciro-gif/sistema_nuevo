import 'package:flutter/widgets.dart';

const double kDesktopBreakpoint = 800;

/// Altura típica del bottom nav del shell móvil.
const double kMobileBottomNavHeight = 56;

/// Espacio extra para FAB sobre el nav / safe area.
const double kFabClearance = 88;

/// Márgenes estándar de páginas.
const EdgeInsets kPagePadding = EdgeInsets.fromLTRB(16, 16, 16, 16);

/// Padding de scroll con espacio inferior para no pisar la barra del sistema.
EdgeInsets pageScrollPadding(BuildContext context, {double extraBottom = 32}) {
  // viewPadding incluye gesture/nav bar del APK; padding a veces da 0.
  final bottom = MediaQuery.viewPaddingOf(context).bottom;
  return EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom + extraBottom);
}
