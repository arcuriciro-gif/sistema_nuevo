import 'package:flutter/material.dart';

/// Barra fija de guardar, por encima de la navegación del sistema (Android).
class FormSaveBar extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  final bool loading;

  const FormSaveBar({
    super.key,
    required this.onPressed,
    this.label = 'GUARDAR',
    this.icon = Icons.save_rounded,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: loading ? null : onPressed,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon),
              label: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Padding inferior extra para contenido scrolleable (evita tapar con gestos).
EdgeInsets formScrollPadding(BuildContext context, {double base = 16}) {
  final bottom = MediaQuery.viewPaddingOf(context).bottom;
  return EdgeInsets.fromLTRB(base, base, base, base + bottom + 8);
}
