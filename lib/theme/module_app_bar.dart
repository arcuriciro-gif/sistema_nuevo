import 'package:flutter/material.dart';

/// AppBar consistente para módulos y pantallas apiladas.
/// Muestra flecha de volver solo cuando hay ruta previa (`Navigator.canPop`).
AppBar buildModuleAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
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
    actions: actions,
    bottom: bottom,
  );
}
