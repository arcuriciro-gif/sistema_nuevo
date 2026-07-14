import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/firebase/firebase_safe_mode.dart';
import '../services/app_log.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
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
  bool _huellaDisponible = false;
  bool _huellaActivada = false;

  bool get _googleDisponible =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  bool get _esAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (FirebaseSafeMode.enabled) {
      _info =
          'Modo seguro: la app se cerró antes al conectar Firebase. '
          'Podés entrar con usuario local (admin / admin123 la primera vez). '
          'La sync se reintenta después de entrar.';
    }
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
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted && !_loading) await _loginHuella(auto: true);
    }
  }

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _irDespuesDelLogin({bool ofrecerHuella = true}) async {
    final user = AuthService.instance.currentUser;
    if (user == null || !mounted) return;

    await appendAppLog(
      'NAV post-login debeCambiar=${user.debeCambiarPassword}',
    );

    if (user.debeCambiarPassword) {
      if (!mounted) return;
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
            title: const Text('¿Entrar más rápido?'),
            content: const Text(
              'La próxima vez podés desbloquear Tata.Manager con la huella, '
              'el rostro o el PIN/patrón del celular.',
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
                SnackBar(content: Text(AuthService.mensajeUsuario(e))),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AuthService.instance.conectarFirebaseDespuesDelLogin();
    });
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
      await _irDespuesDelLogin(ofrecerHuella: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!auto) {
          _error = AuthService.mensajeUsuario(e);
        }
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = FirebaseSafeMode.enabled ? _info : null;
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

      await _irDespuesDelLogin();
    } catch (e, st) {
      debugPrint('Login crash: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Error al iniciar sesión: $e. '
            'Probá con admin / admin123 (primera vez en esta PC).';
      });
    }
  }

  Future<void> _loginGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.loginConGoogle();
      if (!mounted) return;
      setState(() => _loading = false);
      await _irDespuesDelLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
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

  Future<void> _salirModoSeguro() async {
    await FirebaseSafeMode.desactivar();
    if (!mounted) return;
    setState(() {
      _info =
          'Modo seguro desactivado. Reiniciá la app para volver a usar Firebase.';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final branding = BrandingService.instance;
    final logoPath = branding.imagenUiPath;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                          'Primera vez: admin / admin123. '
                          'Empleados: preferí Google con el Gmail que te cargó el admin. '
                          'Nube: Configuración → Activar sincronización.',
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
                                Icons.info_outline,
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
                        if (_huellaActivada) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed:
                                  _loading ? null : () => _loginHuella(),
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: const Text(
                                'Entrar con huella / rostro',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                        if (_googleDisponible) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _loginGoogle,
                              icon: const Icon(Icons.g_mobiledata_rounded),
                              label: const Text('Continuar con Google'),
                            ),
                          ),
                        ],
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
                        if (FirebaseSafeMode.enabled)
                          TextButton(
                            onPressed: _salirModoSeguro,
                            child: const Text('Desactivar modo seguro'),
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
      ),
    );
  }
}
