import 'package:flutter/material.dart';

import '../core/auth/rol_util.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/usuario_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/form_save_bar.dart';

class UsuarioFormPage extends StatefulWidget {
  final Usuario? usuario;

  const UsuarioFormPage({super.key, this.usuario});

  @override
  State<UsuarioFormPage> createState() => _UsuarioFormPageState();
}

class _UsuarioFormPageState extends State<UsuarioFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _usuarioController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();

  final UsuarioService _service = UsuarioService.instance;
  bool _guardando = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _activo = true;
  String _rol = RolUtil.empleado;
  bool _sinPermiso = false;

  bool get _esEdicion => widget.usuario != null;

  @override
  void initState() {
    super.initState();
    if (!AuthService.instance.esAdministrador()) {
      _sinPermiso = true;
      return;
    }
    final usuario = widget.usuario;
    _nombreController.text = usuario?.nombre ?? '';
    _usuarioController.text = usuario?.usuario ?? '';
    _emailController.text = usuario?.email ?? '';
    _activo = usuario?.activo ?? true;
    _rol = RolUtil.normalizar(usuario?.rol ?? RolUtil.empleado);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _usuarioController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _guardando = true);
    try {
      final usuarioTexto = _usuarioController.text.trim();
      final emailTexto = _emailController.text.trim();
      final cambiaUsuario = !_esEdicion ||
          widget.usuario!.usuario.toLowerCase() != usuarioTexto.toLowerCase();
      if (cambiaUsuario && await _service.existeUsuario(usuarioTexto)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Ya existe un usuario con ese nombre.')),
        );
        setState(() => _guardando = false);
        return;
      }

      final usuario = Usuario(
        id: widget.usuario?.id,
        firebaseUid: widget.usuario?.firebaseUid,
        nombre: _nombreController.text.trim(),
        usuario: usuarioTexto,
        password: widget.usuario?.password ?? _passwordController.text,
        rol: _rol,
        activo: _activo,
        debeCambiarPassword: widget.usuario?.debeCambiarPassword ?? !_esEdicion,
        email: emailTexto,
        foto: widget.usuario?.foto ?? '',
        fechaCreacion: widget.usuario?.fechaCreacion ?? DateTime.now(),
        ultimoAcceso: widget.usuario?.ultimoAcceso,
      );

      if (_esEdicion) {
        await _service.actualizar(
          usuario,
          nuevaPassword: _passwordController.text.trim().isEmpty
              ? null
              : _passwordController.text.trim(),
        );
        if (!mounted) return;
        navigator.pop(true);
      } else {
        final resultado = await _service.insertarConAviso(usuario);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Usuario creado'),
            content: Text(
              resultado.aviso ??
                  (resultado.emailEnviado
                      ? 'Se envió la confirmación por email.'
                      : 'Usuario dado de alta correctamente.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        navigator.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  InputDecoration _decoracion(
    String label,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sinPermiso) {
      return Scaffold(
        appBar: buildModuleAppBar(context, title: 'Usuario'),
        body: const Center(
          child: Text('Solo el administrador puede gestionar usuarios.'),
        ),
      );
    }

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: _esEdicion ? 'Editar usuario' : 'Nuevo usuario',
      ),
      bottomNavigationBar: FormSaveBar(
        onPressed: _guardando ? null : _guardar,
        loading: _guardando,
        label: _esEdicion ? 'ACTUALIZAR' : 'CREAR USUARIO',
      ),
      body: SingleChildScrollView(
        padding: formScrollPadding(context),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: _decoracion('Nombre completo', Icons.badge_outlined),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Ingresá el nombre'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usuarioController,
                decoration: _decoracion('Usuario', Icons.person_outline_rounded),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Ingresá el usuario'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoracion(
                  'Email (confirmación)',
                  Icons.email_outlined,
                ),
                validator: (value) {
                  if (_esEdicion) return null;
                  final v = (value ?? '').trim();
                  if (v.isEmpty) {
                    return 'Ingresá un email real para enviar la confirmación';
                  }
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Email inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _rol,
                decoration: _decoracion('Rol', Icons.security_rounded),
                items: RolUtil.rolesAsignables
                    .map(
                      (rol) => DropdownMenuItem(
                        value: rol,
                        child: Text(RolUtil.etiqueta(rol)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _rol = value);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure1,
                decoration: _decoracion(
                  _esEdicion ? 'Nueva contraseña (opcional)' : 'Contraseña',
                  Icons.lock_outline_rounded,
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                    icon: Icon(
                      _obscure1
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (!_esEdicion && (value == null || value.isEmpty)) {
                    return 'Ingresá la contraseña';
                  }
                  if (value != null && value.isNotEmpty && value.length < 6) {
                    return 'Usá al menos 6 caracteres (Firebase)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmarController,
                obscureText: _obscure2,
                decoration: _decoracion(
                  'Confirmar contraseña',
                  Icons.lock_reset_rounded,
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                    icon: Icon(
                      _obscure2
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (_passwordController.text.isEmpty && _esEdicion) return null;
                  if ((value ?? '') != _passwordController.text) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _activo,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() => _activo = value),
                title: const Text('Usuario activo'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
