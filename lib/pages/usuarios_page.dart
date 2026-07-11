import 'package:flutter/material.dart';

import '../core/auth/rol_util.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/usuario_service.dart';
import '../theme/app_visuals.dart';
import '../core/utils/media_path.dart';
import '../widgets/password_confirm_dialog.dart';
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
  bool _soloPendientes = false;

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
      if (_soloPendientes && !usuario.pendienteAlta) return false;
      return usuario.nombre.toLowerCase().contains(query) ||
          usuario.usuario.toLowerCase().contains(query) ||
          usuario.rol.toLowerCase().contains(query) ||
          usuario.email.toLowerCase().contains(query) ||
          (usuario.pendienteAlta && 'pendiente'.contains(query));
    }).toList()
      ..sort((a, b) {
        if (a.pendienteAlta != b.pendienteAlta) {
          return a.pendienteAlta ? -1 : 1;
        }
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
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

  Future<void> _aprobarAlta(Usuario usuario) async {
    String rol = RolUtil.normalizar(usuario.rol);
    if (rol == RolUtil.administrador) rol = RolUtil.empleado;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Dar de alta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${usuario.nombre}\n${usuario.email}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: rol,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    items: RolUtil.rolesAsignables
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(RolUtil.etiqueta(r)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => rol = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Aprobar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await _service.aprobarAlta(usuario, rol: rol);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${usuario.email} aprobado como ${RolUtil.etiqueta(rol)}.',
          ),
        ),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _eliminarUsuario(Usuario usuario) async {
    final ok = await confirmarConClave(
      context,
      titulo: 'Eliminar usuario',
      mensaje:
          'Vas a eliminar a ${usuario.nombre} (@${usuario.usuario}).\n'
          'No podrá iniciar sesión en ningún dispositivo.\n\n'
          'Ingresá tu contraseña de administrador para confirmar.',
      confirmarLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;

    try {
      await _service.eliminar(usuario.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Usuario ${usuario.usuario} eliminado.')),
      );
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
              'Se actualiza la clave en esta PC y en la nube. '
              'En el celular: mismo usuario y esta misma clave (sin email).',
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
    if (confirmar != true || ctrl.text.trim().length < 6) {
      if (confirmar == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La contraseña debe tener al menos 6 caracteres.'),
          ),
        );
      }
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
            color: AppVisuals.warning(cs).withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cómo dar el alta',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppVisuals.warning(cs),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '1) La persona pide acceso con Google o correo.\n'
                    '2) Aparece acá con badge PENDIENTE ALTA (arriba de la lista).\n'
                    '3) Tocá el ícono de persona con tilde → elegí rol → Aprobar.\n'
                    '4) Ella vuelve a entrar con el mismo Google/correo.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                selected: _soloPendientes,
                label: Text(
                  'Solo pendientes '
                  '(${_usuarios.where((u) => u.pendienteAlta).length})',
                ),
                onSelected: (v) {
                  setState(() => _soloPendientes = v);
                  _filtrar(_buscarController.text);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _buscarController,
              onChanged: _filtrar,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email, usuario o rol...',
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
                    ? Center(
                        child: Text(
                          _soloPendientes
                              ? 'No hay solicitudes pendientes.'
                              : 'No hay usuarios registrados.',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                        itemCount: _filtrados.length,
                        itemBuilder: (context, index) {
                          final usuario = _filtrados[index];
                          final colorRol = _colorRol(usuario.rol);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: usuario.pendienteAlta
                                ? AppVisuals.warning(cs).withValues(alpha: 0.08)
                                : null,
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
                                          color: (usuario.pendienteAlta
                                                  ? AppVisuals.warning(cs)
                                                  : usuario.activo
                                                      ? AppVisuals.success(cs)
                                                      : AppVisuals.danger(cs))
                                              .withValues(alpha: .15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          usuario.pendienteAlta
                                              ? 'PENDIENTE ALTA'
                                              : usuario.activo
                                                  ? 'ACTIVO'
                                                  : 'INACTIVO',
                                          style: TextStyle(
                                            color: usuario.pendienteAlta
                                                ? AppVisuals.warning(cs)
                                                : usuario.activo
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
                                spacing: 0,
                                children: [
                                  if (usuario.pendienteAlta)
                                    IconButton(
                                      onPressed: () => _aprobarAlta(usuario),
                                      icon: Icon(
                                        Icons.how_to_reg_rounded,
                                        color: AppVisuals.success(cs),
                                      ),
                                      tooltip: 'Dar de alta',
                                    ),
                                  IconButton(
                                    onPressed: () =>
                                        _abrirFormulario(usuario: usuario),
                                    icon: const Icon(Icons.edit_rounded),
                                    tooltip: 'Editar',
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        _restablecerPassword(usuario),
                                    icon: const Icon(Icons.lock_reset_rounded),
                                    tooltip: 'Restablecer contraseña',
                                  ),
                                  if (!usuario.pendienteAlta)
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
                                  IconButton(
                                    onPressed:
                                        usuario.id ==
                                                AuthService
                                                    .instance.currentUser?.id
                                            ? null
                                            : () => _eliminarUsuario(usuario),
                                    icon: Icon(
                                      Icons.delete_forever_rounded,
                                      color: usuario.id ==
                                              AuthService
                                                  .instance.currentUser?.id
                                          ? cs.onSurfaceVariant
                                          : AppVisuals.danger(cs),
                                    ),
                                    tooltip: 'Eliminar',
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
