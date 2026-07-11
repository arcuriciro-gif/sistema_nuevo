import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_version.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import 'cambiar_password_obligatorio_page.dart';
import 'main_shell.dart';
import 'manual_usuario_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool get _googleDisponible =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isLinux);

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _irTrasLogin({required bool forzarCambioClave}) async {
    if (!mounted) return;
    if (forzarCambioClave) {
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
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = await AuthService.instance.login(
      _usuarioCtrl.text.trim(),
      _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (user == null) {
      setState(() {
        _error =
            'Usuario o contraseña incorrectos.\n'
            'También podés usar “Entrar con Google” si el admin cargó tu Gmail.';
      });
      return;
    }

    final faltaFirebaseAuth =
        FirebaseAuthUsuarioService.instance.disponible &&
        FirebaseAuthUsuarioService.instance.uidActual == null;
    final passwordCorta = _passwordCtrl.text.length < 6;

    await _irTrasLogin(
      forzarCambioClave:
          user.debeCambiarPassword || (faltaFirebaseAuth && passwordCorta),
    );
  }

  Future<void> _loginGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.loginConGoogle();
      if (!mounted) return;
      setState(() => _loading = false);
      await _irTrasLogin(forzarCambioClave: false);
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
                if (logoPath.isNotEmpty)
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
                      border: Border.all(color: cs.primary, width: 1.5),
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
                          'Empleados: preferí Google con el Gmail que te cargó el admin.',
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (_googleDisponible) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _loginGoogle,
                              icon: const Icon(Icons.g_mobiledata_rounded,
                                  size: 28),
                              label: const Text(
                                'Entrar con Google',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'o con usuario',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _usuarioCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Usuario',
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
                            prefixIcon:
                                const Icon(Icons.lock_outline_rounded),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ManualUsuarioPage(
                            desdeLogin: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text(
                        'Instrucciones / PDF (sin iniciar sesión)'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Inicio de sesión, primeros pasos y uso recomendado del sistema.',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tata.Manager $kAppVersionLabel',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
