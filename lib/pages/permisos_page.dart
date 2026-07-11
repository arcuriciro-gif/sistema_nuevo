import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/permisos_service.dart';
import '../models/permiso.dart';
import '../theme/module_app_bar.dart';

class PermisosPage extends StatefulWidget {
  const PermisosPage({super.key});

  @override
  State<PermisosPage> createState() => _PermisosPageState();
}

class _PermisosPageState extends State<PermisosPage> {
  final PermisosService _service = PermisosService.instance;
  final List<String> _roles = const [
    'admin',
    'supervisor',
    'empleado',
    'solo_lectura',
  ];

  final Map<String, List<Permiso>> _permisos = {};
  bool _cargando = true;
  bool _guardando = false;
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

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    for (final rol in _roles) {
      _permisos[rol] = await _service.obtenerPorRol(rol);
    }
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final n = await _service.guardarLoteConAuditoria(_permisos);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Sin cambios para guardar.'
                : 'Permisos actualizados ($n cambio(s)). Registrado en auditoría.',
          ),
        ),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron guardar los permisos: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _actualizarPermiso(
    String rol,
    int index,
    Permiso Function(Permiso permiso) updater,
  ) {
    final permisos = _permisos[rol];
    if (permisos == null) return;
    permisos[index] = updater(permisos[index]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_sinPermiso) {
      return Scaffold(
        appBar: buildModuleAppBar(context, title: 'Permisos por rol'),
        body: Center(
          child: Text(
            'Solo el administrador puede cambiar permisos.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: _roles.length,
      child: Scaffold(
        appBar: buildModuleAppBar(
          context,
          title: 'Permisos por rol',
          bottom: TabBar(
            isScrollable: true,
            tabs: _roles
                .map(
                  (rol) => Tab(text: rol.replaceAll('_', ' ').toUpperCase()),
                )
                .toList(),
          ),
          actions: [
            TextButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Guardar'),
            ),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Material(
                    color: cs.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Text(
                        'Solo administradores. Los cambios quedan en Auditoría. '
                        'El rol admin conserva acceso a módulos críticos.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: _roles.map((rol) {
                        final permisos = _permisos[rol] ?? const <Permiso>[];
                        return permisos.isEmpty
                            ? const Center(child: Text('Sin permisos cargados.'))
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Módulo')),
                                      DataColumn(label: Text('Ver')),
                                      DataColumn(label: Text('Crear')),
                                      DataColumn(label: Text('Editar')),
                                      DataColumn(label: Text('Eliminar')),
                                    ],
                                    rows: List.generate(permisos.length, (index) {
                                      final permiso = permisos[index];
                                      return DataRow(
                                        cells: [
                                          DataCell(
                                            Text(
                                              permiso.modulo
                                                  .replaceAll('_', ' '),
                                            ),
                                          ),
                                          DataCell(
                                            Checkbox(
                                              value: permiso.puedeVer,
                                              onChanged: (value) =>
                                                  _actualizarPermiso(
                                                rol,
                                                index,
                                                (actual) => Permiso(
                                                  id: actual.id,
                                                  rol: actual.rol,
                                                  modulo: actual.modulo,
                                                  puedeVer: value ?? false,
                                                  puedeCrear: actual.puedeCrear,
                                                  puedeEditar:
                                                      actual.puedeEditar,
                                                  puedeEliminar:
                                                      actual.puedeEliminar,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Checkbox(
                                              value: permiso.puedeCrear,
                                              onChanged: (value) =>
                                                  _actualizarPermiso(
                                                rol,
                                                index,
                                                (actual) => Permiso(
                                                  id: actual.id,
                                                  rol: actual.rol,
                                                  modulo: actual.modulo,
                                                  puedeVer: actual.puedeVer,
                                                  puedeCrear: value ?? false,
                                                  puedeEditar:
                                                      actual.puedeEditar,
                                                  puedeEliminar:
                                                      actual.puedeEliminar,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Checkbox(
                                              value: permiso.puedeEditar,
                                              onChanged: (value) =>
                                                  _actualizarPermiso(
                                                rol,
                                                index,
                                                (actual) => Permiso(
                                                  id: actual.id,
                                                  rol: actual.rol,
                                                  modulo: actual.modulo,
                                                  puedeVer: actual.puedeVer,
                                                  puedeCrear: actual.puedeCrear,
                                                  puedeEditar: value ?? false,
                                                  puedeEliminar:
                                                      actual.puedeEliminar,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Checkbox(
                                              value: permiso.puedeEliminar,
                                              onChanged: (value) =>
                                                  _actualizarPermiso(
                                                rol,
                                                index,
                                                (actual) => Permiso(
                                                  id: actual.id,
                                                  rol: actual.rol,
                                                  modulo: actual.modulo,
                                                  puedeVer: actual.puedeVer,
                                                  puedeCrear: actual.puedeCrear,
                                                  puedeEditar:
                                                      actual.puedeEditar,
                                                  puedeEliminar:
                                                      value ?? false,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              );
                      }).toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
