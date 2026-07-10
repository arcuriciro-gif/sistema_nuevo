import 'package:flutter/material.dart';

import '../core/firebase/firebase_auth_usuario_service.dart';
import '../services/auth_service.dart';
import 'main_shell.dart';

class CambiarPasswordObligatorioPage extends StatefulWidget {
  const CambiarPasswordObligatorioPage({super.key});

  @override
  State<CambiarPasswordObligatorioPage> createState() =>
      _CambiarPasswordObligatorioPageState();
}

class _CambiarPasswordObligatorioPageState
    extends State<CambiarPasswordObligatorioPage> {
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _irAlSistema({String? aviso}) async {
    if (!mounted) return;
    if (aviso != null && aviso.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aviso), duration: const Duration(seconds: 5)),
      );
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  Future<void> _guardar() async {
    final nueva = _nuevaCtrl.text;
    final confirmar = _confirmarCtrl.text;

    if (nueva.length < 6) {
      setState(() {
        _error =
            'La nueva contraseña debe tener al menos 6 caracteres (requisito de Firebase).';
      });
      return;
    }
    if (nueva != confirmar) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.completarCambioPasswordObligatorio(nueva);
      if (!mounted) return;

      final conNube = FirebaseAuthUsuarioService.instance.uidActual != null;
      await _irAlSistema(
        aviso: conNube
            ? null
            : 'Contraseña guardada. La sincronización en la nube quedó pendiente: '
                'revisá Authentication → Correo/contraseña en Firebase, '
                'o usá en el celular la misma clave.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('StateError: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usuario = AuthService.instance.currentUser?.usuario ?? '';
    final sinNube = FirebaseAuthUsuarioService.instance.uidActual == null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Definí tu contraseña',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sinNube
                          ? 'Hola $usuario: elegí una contraseña de al menos 6 caracteres. '
                              'Usá la misma en la PC y en el celular para sincronizar.'
                          : 'Hola $usuario, debés definir una nueva contraseña antes de continuar.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nuevaCtrl,
                      obscureText: _obscure1,
                      decoration: InputDecoration(
                        labelText: 'Nueva contraseña',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure1
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscure1 = !_obscure1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmarCtrl,
                      obscureText: _obscure2,
                      decoration: InputDecoration(
                        labelText: 'Confirmar nueva contraseña',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure2
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscure2 = !_obscure2),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _loading ? null : _guardar(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.error_outline, color: cs.error, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _guardar,
                        child: _loading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Text(
                                'GUARDAR Y CONTINUAR',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
