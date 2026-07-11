import 'package:flutter/material.dart';

import '../core/auth/rol_util.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/usuario_service.dart';
import '../theme/app_visuals.dart';
import '../core/utils/media_path.dart';
import 'usuario_form_page.dart';
import '../theme/module_app_bar.dart';

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  final UsuarioService _service = UsuarioService.instance;
  final TextEditingController _buscarController = TextEditingController();

  List<Usuario> _usuarios = [];
  List<Usuario> _filtrados = [];
  bool _cargando = true;
  bool _sinPermiso = false;

  @override
  void initState() {
    super.initState();
    if (!AuthService.instance.esAdministrador()) {
      _sinPermiso = true;
      _cargando = false;
      return;
    }
    _cargar();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    _usuarios = await _service.obtenerTodos();
    _filtrar(_buscarController.text, refrescar: false);
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  void _filtrar(String texto, {bool refrescar = true}) {
    final query = texto.trim().toLowerCase();
    _filtrados = _usuarios.where((usuario) {
      return usuario.nombre.toLowerCase().contains(query) ||
          usuario.usuario.toLowerCase().contains(query) ||
          usuario.rol.toLowerCase().contains(query);
    }).toList();
    if (refrescar && mounted) setState(() {});
  }

  Future<void> _abrirFormulario({Usuario? usuario}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UsuarioFormPage(usuario: usuario)),
    );
    await _cargar();
  }

  Future<void> _toggleActivo(Usuario usuario) async {
    try {
      if (!usuario.activo) {
        await _service.activar(usuario.id!);
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Desactivar usuario'),
            content: Text(
              '¿Desactivar a ${usuario.nombre}? No podrá iniciar sesión.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Desactivar'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await _service.desactivar(usuario.id!);
      }
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _restablecerPassword(Usuario usuario) async {
    final ctrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restablecer contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usuario: ${usuario.usuario}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña temporal',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Deberá cambiarla al ingresar. Si tiene email, también se intenta enviar reset de Firebase.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (confirmar != true || ctrl.text.trim().length < 4) {
      ctrl.dispose();
      return;
    }

    try {
      final aviso =
          await _service.restablecerPassword(usuario, ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            aviso ??
                'Contraseña restablecida para ${usuario.usuario}. Deberá cambiarla al ingresar.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo restablecer: $e')),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Color _colorRol(String rol) {
    final cs = Theme.of(context).colorScheme;
    switch (RolUtil.normalizar(rol)) {
      case RolUtil.administrador:
        return AppVisuals.danger(cs);
      case RolUtil.encargado:
        return AppVisuals.warning(cs);
      default:
        return AppVisuals.success(cs);
    }
  }

  String _textoFecha(DateTime? fecha) {
    if (fecha == null) return 'Nunca';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_sinPermiso) {
      return Scaffold(
        appBar: buildModuleAppBar(context, title: 'Usuarios'),
        body: Center(
          child: Text(
            'Solo el administrador puede gestionar usuarios.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Usuarios'),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_usuarios',
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo usuario'),
      ),
      body: Column(
        children: [
          Material(
            color: cs.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Solo administrador: alta, edición, desactivar y restablecer contraseña. Todo queda en Auditoría.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _buscarController,
              onChanged: _filtrar,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, usuario o rol...',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _filtrados.isEmpty
                    ? const Center(child: Text('No hay usuarios registrados.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                        itemCount: _filtrados.length,
                        itemBuilder: (context, index) {
                          final usuario = _filtrados[index];
                          final colorRol = _colorRol(usuario.rol);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorRol.withValues(alpha: .15),
                                backgroundImage:
                                    imageProviderDesdePath(usuario.foto),
                                child: usuario.foto.isEmpty
                                    ? Text(
                                        usuario.nombre
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: colorRol,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                usuario.nombre,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('@${usuario.usuario}'),
                                  if (usuario.email.isNotEmpty)
                                    Text(
                                      usuario.email,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorRol.withValues(alpha: .15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          RolUtil.etiqueta(usuario.rol).toUpperCase(),
                                          style: TextStyle(
                                            color: colorRol,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (usuario.activo
                                                  ? AppVisuals.success(cs)
                                                  : AppVisuals.danger(cs))
                                              .withValues(alpha: .15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          usuario.activo ? 'ACTIVO' : 'INACTIVO',
                                          style: TextStyle(
                                            color: usuario.activo
                                                ? AppVisuals.success(cs)
                                                : AppVisuals.danger(cs),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Último acceso: ${_textoFecha(usuario.ultimoAcceso)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    onPressed: () => _abrirFormulario(usuario: usuario),
                                    icon: const Icon(Icons.edit_rounded),
                                    tooltip: 'Editar',
                                  ),
                                  IconButton(
                                    onPressed: () => _restablecerPassword(usuario),
                                    icon: const Icon(Icons.lock_reset_rounded),
                                    tooltip: 'Restablecer contraseña',
                                  ),
                                  IconButton(
                                    onPressed: () => _toggleActivo(usuario),
                                    icon: Icon(
                                      usuario.activo
                                          ? Icons.toggle_on_rounded
                                          : Icons.toggle_off_rounded,
                                    ),
                                    tooltip: usuario.activo
                                        ? 'Desactivar'
                                        : 'Activar',
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
