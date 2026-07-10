import 'package:flutter/material.dart';

import '../models/permiso.dart';
import '../services/permisos_service.dart';

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

  @override
  void initState() {
    super.initState();
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
      for (final rol in _roles) {
        for (final permiso in _permisos[rol] ?? const <Permiso>[]) {
          await _service.actualizar(permiso);
        }
      }
      await _service.cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permisos actualizados correctamente.')),
      );
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
    return DefaultTabController(
      length: _roles.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Permisos por rol'),
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
            : TabBarView(
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
                                        permiso.modulo.replaceAll('_', ' '),
                                      ),
                                    ),
                                    DataCell(
                                      Checkbox(
                                        value: permiso.puedeVer,
                                        onChanged: (value) => _actualizarPermiso(
                                          rol,
                                          index,
                                          (actual) => Permiso(
                                            id: actual.id,
                                            rol: actual.rol,
                                            modulo: actual.modulo,
                                            puedeVer: value ?? false,
                                            puedeCrear: actual.puedeCrear,
                                            puedeEditar: actual.puedeEditar,
                                            puedeEliminar: actual.puedeEliminar,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Checkbox(
                                        value: permiso.puedeCrear,
                                        onChanged: (value) => _actualizarPermiso(
                                          rol,
                                          index,
                                          (actual) => Permiso(
                                            id: actual.id,
                                            rol: actual.rol,
                                            modulo: actual.modulo,
                                            puedeVer: actual.puedeVer,
                                            puedeCrear: value ?? false,
                                            puedeEditar: actual.puedeEditar,
                                            puedeEliminar: actual.puedeEliminar,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Checkbox(
                                        value: permiso.puedeEditar,
                                        onChanged: (value) => _actualizarPermiso(
                                          rol,
                                          index,
                                          (actual) => Permiso(
                                            id: actual.id,
                                            rol: actual.rol,
                                            modulo: actual.modulo,
                                            puedeVer: actual.puedeVer,
                                            puedeCrear: actual.puedeCrear,
                                            puedeEditar: value ?? false,
                                            puedeEliminar: actual.puedeEliminar,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Checkbox(
                                        value: permiso.puedeEliminar,
                                        onChanged: (value) => _actualizarPermiso(
                                          rol,
                                          index,
                                          (actual) => Permiso(
                                            id: actual.id,
                                            rol: actual.rol,
                                            modulo: actual.modulo,
                                            puedeVer: actual.puedeVer,
                                            puedeCrear: actual.puedeCrear,
                                            puedeEditar: actual.puedeEditar,
                                            puedeEliminar: value ?? false,
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
    );
  }
}
