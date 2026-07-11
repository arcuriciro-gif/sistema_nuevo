import 'package:flutter/material.dart';

import '../core/navigation/app_navigation.dart';

/// AppBar consistente para módulos y pantallas apiladas.
///
/// - Flecha volver: solo si hay ruta previa.
/// - Botón Inicio: vuelve al inicio en un solo toque (cierra el stack).
AppBar buildModuleAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  bool showHome = true,
}) {
  final puedeVolver = Navigator.of(context).canPop();
  return AppBar(
    title: Text(title),
    leading: puedeVolver
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          )
        : null,
    automaticallyImplyLeading: puedeVolver,
    actions: [
      if (showHome)
        IconButton(
          tooltip: 'Inicio',
          icon: const Icon(Icons.home_rounded),
          onPressed: () => AppNavigation.irAlInicio(context),
        ),
      ...?actions,
    ],
    bottom: bottom,
  );
}
