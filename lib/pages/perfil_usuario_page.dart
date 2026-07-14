import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/sync/media_sync_service.dart';
import '../core/utils/media_path.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../theme/module_app_bar.dart';

/// Perfil del usuario logueado: foto, nombre, usuario y contraseña.
class PerfilUsuarioPage extends StatefulWidget {
  const PerfilUsuarioPage({super.key});

  @override
  State<PerfilUsuarioPage> createState() => _PerfilUsuarioPageState();
}

class _PerfilUsuarioPageState extends State<PerfilUsuarioPage> {
  final _nombreCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passActualCtrl = TextEditingController();
  final _passNuevaCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  String _foto = '';
  bool _guardando = false;
  bool _cambiandoPass = false;
  bool _obscureActual = true;
  bool _obscureNueva = true;
  bool _obscureConfirm = true;
  bool _huellaSoportada = false;
  bool _huellaActivada = false;
  bool _huellaCambiando = false;

  bool get _esAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    final u = AuthService.instance.currentUser;
    _nombreCtrl.text = u?.nombre ?? '';
    _usuarioCtrl.text = u?.usuario ?? '';
    _emailCtrl.text = u?.email ?? '';
    _foto = u?.foto ?? '';
    _cargarHuella();
  }

  Future<void> _cargarHuella() async {
    if (!_esAndroid) return;
    final bio = BiometricAuthService.instance;
    final soporta = await bio.dispositivoSoporta();
    final on = soporta && await bio.estaActivada();
    if (!mounted) return;
    setState(() {
      _huellaSoportada = soporta;
      _huellaActivada = on;
    });
  }

  Future<void> _toggleHuella(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _huellaCambiando = true);
    try {
      if (value) {
        await AuthService.instance.activarDesbloqueoHuella();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Desbloqueo biométrico activado'),
          ),
        );
      } else {
        await BiometricAuthService.instance.desactivar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Desbloqueo biométrico desactivado')),
        );
      }
      await _cargarHuella();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AuthService.mensajeUsuario(e))));
      await _cargarHuella();
    } finally {
      if (mounted) setState(() => _huellaCambiando = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _usuarioCtrl.dispose();
    _emailCtrl.dispose();
    _passActualCtrl.dispose();
    _passNuevaCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 800,
    );
    if (img == null) return;

    setState(() => _guardando = true);
    try {
      final u = AuthService.instance.currentUser;
      final key = u?.firebaseUid?.isNotEmpty == true
          ? u!.firebaseUid!
          : (u?.usuario ?? 'user');
      final url = await MediaSyncService.instance.subirFotoUsuario(
        uidOrUsuario: key,
        file: File(img.path),
      );
      setState(() => _foto = url ?? img.path);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardarPerfil() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);
    try {
      final usuarioActual = AuthService.instance.currentUser?.usuario ?? '';
      final cambiaUsuario =
          _usuarioCtrl.text.trim().toLowerCase() != usuarioActual.toLowerCase();
      await AuthService.instance.actualizarPerfilPropio(
        nombre: _nombreCtrl.text.trim(),
        usuario: _usuarioCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        foto: _foto,
        passwordActual: cambiaUsuario ? _passActualCtrl.text : null,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Perfil actualizado')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cambiarPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final nueva = _passNuevaCtrl.text;
    if (nueva.length < 6) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('La nueva contraseña debe tener al menos 6 caracteres'),
        ),
      );
      return;
    }
    if (nueva != _passConfirmCtrl.text) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }
    setState(() => _cambiandoPass = true);
    try {
      await AuthService.instance.cambiarPasswordPropio(
        passwordActual: _passActualCtrl.text,
        passwordNueva: nueva,
      );
      if (!mounted) return;
      _passActualCtrl.clear();
      _passNuevaCtrl.clear();
      _passConfirmCtrl.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _cambiandoPass = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = AuthService.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Mi perfil'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _guardando ? null : _elegirFoto,
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: imageProviderDesdePath(_foto),
                    child: _foto.isEmpty
                        ? Text(
                            (u?.nombre.isNotEmpty == true
                                    ? u!.nombre[0]
                                    : 'U')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 36,
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _guardando ? null : _elegirFoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cambiar foto'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre para mostrar',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usuarioCtrl,
            decoration: const InputDecoration(
              labelText: 'Usuario (login)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
              helperText: 'Si lo cambiás, pedimos tu contraseña actual abajo',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
              helperText: 'Para avisos y recuperación de contraseña',
            ),
          ),
          const SizedBox(height: 16),
          if (_huellaSoportada) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Entrar con biometría'),
              subtitle: const Text(
                'Huella, rostro o PIN/patrón del celular en este dispositivo',
              ),
              value: _huellaActivada,
              onChanged: _huellaCambiando ? null : _toggleHuella,
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardarPerfil,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Guardar perfil'),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Cambiar contraseña',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passActualCtrl,
            obscureText: _obscureActual,
            decoration: InputDecoration(
              labelText: 'Contraseña actual',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscureActual = !_obscureActual),
                icon: Icon(
                  _obscureActual
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passNuevaCtrl,
            obscureText: _obscureNueva,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureNueva = !_obscureNueva),
                icon: Icon(
                  _obscureNueva
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passConfirmCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirmar nueva contraseña',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _cambiandoPass ? null : _cambiarPassword,
              icon: _cambiandoPass
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key_rounded),
              label: const Text('Actualizar contraseña'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
