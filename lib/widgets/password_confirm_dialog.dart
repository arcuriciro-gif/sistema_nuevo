import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_visuals.dart';

/// Diálogo de confirmación que exige la contraseña del usuario en sesión.
Future<bool> confirmarConClave(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String confirmarLabel = 'Confirmar',
  bool peligroso = true,
}) async {
  final ctrl = TextEditingController();
  final cs = Theme.of(context).colorScheme;
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(titulo),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mensaje),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Tu contraseña',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                  onSubmitted: (_) {
                    if (!AuthService.instance.verificarPassword(ctrl.text)) {
                      setLocal(() => error = 'Contraseña incorrecta');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: peligroso
                    ? FilledButton.styleFrom(
                        backgroundColor: AppVisuals.danger(cs),
                      )
                    : null,
                onPressed: () {
                  if (!AuthService.instance.verificarPassword(ctrl.text)) {
                    setLocal(() => error = 'Contraseña incorrecta');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(confirmarLabel),
              ),
            ],
          );
        },
      );
    },
  );
  ctrl.dispose();
  return ok == true;
}
