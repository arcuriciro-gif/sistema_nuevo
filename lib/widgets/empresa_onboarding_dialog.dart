import 'package:flutter/material.dart';

import '../core/config/backend_config_service.dart';
import '../services/auth_service.dart';

/// Explica el modelo empresa/dispositivos y evita quedarse en un tenant fantasma.
class EmpresaOnboardingDialog extends StatefulWidget {
  const EmpresaOnboardingDialog({super.key});

  /// Muestra el diálogo si hace falta (admin + empresa no confirmada).
  static Future<void> mostrarSiHaceFalta(BuildContext context) async {
    if (!AuthService.instance.esAdministrador()) return;
    final cfg = BackendConfigService.instance;
    if (cfg.empresaConfirmada && !cfg.esEmpresaAutogenerada) return;
    if (cfg.empresaConfirmada) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const EmpresaOnboardingDialog(),
    );
  }

  @override
  State<EmpresaOnboardingDialog> createState() =>
      _EmpresaOnboardingDialogState();
}

class _EmpresaOnboardingDialogState extends State<EmpresaOnboardingDialog> {
  final _codigoCtrl = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _unirA(String codigo) async {
    final nuevo = codigo.trim();
    if (nuevo.isEmpty) {
      setState(() => _error = 'Ingresá el código de empresa.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final anterior = BackendConfigService.instance.tenantId;
      await BackendConfigService.instance.setTenantId(nuevo);
      if (BackendConfigService.instance.firebaseEnabled) {
        await AuthService.instance.desactivarNube();
      }
      if (!mounted) return;
      Navigator.pop(context);
      if (!mounted) return;
      final mismo = anterior == nuevo;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mismo
                ? 'Empresa "$nuevo" confirmada.'
                : 'Empresa "$nuevo" guardada. Cerrá sesión, entrá de nuevo '
                    'con la misma clave que en la PC y activá la sincronización.',
          ),
          duration: const Duration(seconds: 7),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e';
      });
    }
  }

  Future<void> _confirmarNueva() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await BackendConfigService.instance.confirmarEmpresaActual();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Elegí la empresa'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresá el código de la empresa para unirte, '
              'o creá una empresa nueva en este dispositivo.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _guardando
                  ? null
                  : () => _unirA(BackendConfigService.legacySharedTenantId),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Unirme a tata_stock'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codigoCtrl,
              decoration: const InputDecoration(
                labelText: 'Código de empresa',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _guardando
                  ? null
                  : () => _unirA(_codigoCtrl.text),
              child: const Text('Usar este código'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _guardando ? null : _confirmarNueva,
              child: const Text('Crear empresa nueva'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
