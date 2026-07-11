import 'package:flutter/material.dart';

/// Puente liviano entre pantallas apiladas y [MainShell].
/// No cambia la arquitectura: solo un callback registrado por el shell.
class AppNavigation {
  AppNavigation._();

  /// Selecciona el módulo Inicio en el shell (sin recrear rutas).
  static VoidCallback? irAModuloInicio;

  /// Cierra pantallas apiladas y vuelve a Inicio en un solo toque.
  static void irAlInicio(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    // Post-frame: el popUntil puede no haber terminado el frame del shell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      irAModuloInicio?.call();
    });
  }
}
