import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_version.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
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
  bool _huellaDisponible = false;
  bool _huellaActivada = false;

  bool get _googleDisponible =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isLinux);

  bool get _esAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _prepararHuella();
  }

  Future<void> _prepararHuella() async {
    if (!_esAndroid) return;
    final bio = BiometricAuthService.instance;
    final soporta = await bio.dispositivoSoporta();
    final activada = soporta && await bio.estaActivada();
    if (!mounted) return;
    setState(() {
      _huellaDisponible = soporta;
      _huellaActivada = activada;
    });
    if (activada) {
      // Ofrecer desbloqueo automático al abrir.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted && !_loading) await _loginHuella(auto: true);
    }
  }

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _irTrasLogin({
    required bool forzarCambioClave,
    bool ofrecerHuella = true,
  }) async {
    if (!mounted) return;
    if (forzarCambioClave) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const CambiarPasswordObligatorioPage(),
        ),
      );
      return;
    }
    if (ofrecerHuella && _esAndroid && _huellaDisponible) {
      final ya = await BiometricAuthService.instance.estaActivada();
      if (!ya && mounted) {
        final activar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Entrar con huella?'),
            content: const Text(
              'La próxima vez podés desbloquear Tata.Manager con la huella '
              'del celular, sin tipear usuario ni Google.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Ahora no'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Activar'),
              ),
            ],
          ),
        );
        if (activar == true) {
          try {
            await AuthService.instance.activarDesbloqueoHuella();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e')),
              );
            }
          }
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  Future<void> _loginHuella({bool auto = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.loginConHuella();
      if (!mounted) return;
      setState(() => _loading = false);
      await _irTrasLogin(forzarCambioClave: false, ofrecerHuella: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!auto) {
          _error = e.toString().replaceFirst('StateError: ', '');
        }
      });
    }
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

  Future<void> _loginCorreo() async {
    final nombreCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrar / solicitar con correo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Si es la primera vez, se envía una solicitud al administrador. '
                'Cuando te den el alta, entrá de nuevo con el mismo correo.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo (Gmail u otro)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña (mín. 6)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    final nombre = nombreCtrl.text;
    final email = emailCtrl.text;
    final pass = passCtrl.text;
    nombreCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    if (ok != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.loginORegistrarConEmail(
        email: email,
        password: pass,
        nombre: nombre,
      );
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
                          'Pedí acceso con Google o correo. El administrador te da el alta.',
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_huellaActivada) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : () => _loginHuella(),
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: const Text(
                                'Entrar con huella',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_googleDisponible) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _loginGoogle,
                              icon: const Icon(Icons.g_mobiledata_rounded,
                                  size: 28),
                              label: const Text(
                                'Continuar con Google',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _loginCorreo,
                            icon: const Icon(Icons.email_outlined),
                            label: const Text(
                              'Continuar con correo',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Teléfono: próximamente. Por ahora usá Google o correo.',
                          style: textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
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
                                'admin / usuario local',
                                style: textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
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
