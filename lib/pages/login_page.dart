import 'dart:io';

import 'package:flutter/material.dart';

import '../core/firebase/firebase_auth_usuario_service.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import 'cambiar_password_obligatorio_page.dart';
import 'main_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _recuperando = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      final user = await AuthService.instance.login(
        _usuarioCtrl.text.trim(),
        _passwordCtrl.text,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      if (user == null) {
        setState(() {
          _error = AuthService.instance.lastLoginError ??
              'Usuario o contraseña incorrectos.';
        });
        return;
      }

      final faltaFirebaseAuth =
          FirebaseAuthUsuarioService.instance.disponible &&
          FirebaseAuthUsuarioService.instance.uidActual == null;

      // Sin sesión Firebase no se puede escribir en Firestore (reglas request.auth).
      // Si la clave actual es corta (<6), hay que definir una nueva.
      if (user.debeCambiarPassword || faltaFirebaseAuth) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CambiarPasswordObligatorioPage(),
          ),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } catch (e, st) {
      debugPrint('Login crash: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Error al iniciar sesión: $e. '
            'Si la app se cerraba antes, reintentá. '
            'Revisá que abriste toda la carpeta Instalador_Windows (no solo el .exe).';
      });
    }
  }

  Future<void> _olvidePassword() async {
    final entrada = _usuarioCtrl.text.trim();
    if (entrada.isEmpty) {
      setState(() {
        _error = 'Ingresá tu usuario o email arriba y después tocá recuperar.';
        _info = null;
      });
      return;
    }

    setState(() {
      _recuperando = true;
      _error = null;
      _info = null;
    });

    try {
      await AuthService.instance.enviarRecuperacionPassword(entrada);
      if (!mounted) return;
      setState(() {
        _info =
            'Te enviamos un email para definir/recuperar la contraseña. '
            'El enlace abre el navegador; cuando termines, volvé acá e ingresá '
            'con tu usuario y la nueva clave.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('StateError: ', '');
      });
    } finally {
      if (mounted) setState(() => _recuperando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = BrandingService.instance;
    final logoPath = branding.imagenUiPath;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / branding
                if (logoPath.isNotEmpty && File(logoPath).existsSync())
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: FileImage(File(logoPath)),
                  )
                else
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.store_rounded,
                        size: 48,
                        color: cs.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  branding.nombre,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (branding.slogan.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    branding.slogan,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 40),
                // Login card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Iniciar sesión',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Podés usar tu usuario o el email. '
                          'Si te llegó el mail de confirmación, definí la clave en el navegador y después entrá acá.',
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _usuarioCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Usuario o email',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _loading ? null : _login(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: cs.error,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_info != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.mark_email_read_outlined,
                                color: cs.primary,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _info!,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.primary,
                                  ),
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
                            onPressed: _loading ? null : _login,
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
                                    'ENTRAR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      letterSpacing: 1,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: (_loading || _recuperando)
                                ? null
                                : _olvidePassword,
                            child: _recuperando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Olvidé mi contraseña'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
