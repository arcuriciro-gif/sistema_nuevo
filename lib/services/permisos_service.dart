import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/auth/rol_util.dart';
import '../database/database_helper.dart';
import '../models/permiso.dart';
import 'auth_service.dart';

class PermisosService {
  static final PermisosService instance = PermisosService._();
  PermisosService._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Map<String, Map<String, Permiso>> _cache = {};

  String _normalizarRol(String rol) => RolUtil.clavePermisos(rol);

  void _requiereAdministrador() {
    if (!AuthService.instance.esAdministrador()) {
      throw StateError('Solo el administrador puede modificar permisos.');
    }
  }

  Future<void> cargar() async {
    final db = await _dbHelper.database;
    final rows = await db.query('permisos', orderBy: 'rol, modulo');
    _cache.clear();
    for (final row in rows) {
      final permiso = Permiso.fromMap(row);
      final rol = _normalizarRol(permiso.rol);
      _cache.putIfAbsent(rol, () => {});
      _cache[rol]![permiso.modulo] = permiso;
    }
  }

  Permiso? _buscar(String rol, String modulo) {
    return _cache[_normalizarRol(rol)]?[modulo];
  }

  bool puedeVer(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol) && _cache.isEmpty) return true;
    return _buscar(rol, modulo)?.puedeVer ?? false;
  }

  bool puedeCrear(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol) && _cache.isEmpty) return true;
    return _buscar(rol, modulo)?.puedeCrear ?? false;
  }

  bool puedeEditar(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol) && _cache.isEmpty) return true;
    return _buscar(rol, modulo)?.puedeEditar ?? false;
  }

  bool puedeEliminar(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol) && _cache.isEmpty) return true;
    return _buscar(rol, modulo)?.puedeEliminar ?? false;
  }

  Future<List<Permiso>> obtenerPorRol(String rol) async {
    final normalizado = _normalizarRol(rol);
    if (_cache.containsKey(normalizado)) {
      final permisos = _cache[normalizado]!.values.toList();
      permisos.sort((a, b) => a.modulo.compareTo(b.modulo));
      return permisos;
    }

    final db = await _dbHelper.database;
    final rows = await db.query(
      'permisos',
      where: 'rol = ?',
      whereArgs: [normalizado],
      orderBy: 'modulo',
    );
    return rows.map(Permiso.fromMap).toList();
  }

  String _firma(Permiso p) =>
      '${p.puedeVer ? 1 : 0}${p.puedeCrear ? 1 : 0}'
      '${p.puedeEditar ? 1 : 0}${p.puedeEliminar ? 1 : 0}';

  /// El rol admin siempre conserva acceso total a módulos críticos.
  Permiso _protegerAdmin(Permiso permiso) {
    if (_normalizarRol(permiso.rol) != 'admin') return permiso;
    const criticos = {
      'usuarios',
      'auditoria',
      'configuracion',
      'backup',
      'dashboard',
    };
    if (!criticos.contains(permiso.modulo)) return permiso;
    return Permiso(
      id: permiso.id,
      rol: permiso.rol,
      modulo: permiso.modulo,
      puedeVer: true,
      puedeCrear: true,
      puedeEditar: true,
      puedeEliminar: true,
    );
  }

  Future<void> actualizar(Permiso permiso) async {
    _requiereAdministrador();
    final db = await _dbHelper.database;
    final rol = _normalizarRol(permiso.rol);
    final actualizado = _protegerAdmin(
      Permiso(
        id: permiso.id,
        rol: rol,
        modulo: permiso.modulo,
        puedeVer: permiso.puedeVer,
        puedeCrear: permiso.puedeCrear,
        puedeEditar: permiso.puedeEditar,
        puedeEliminar: permiso.puedeEliminar,
      ),
    );

    final existentes = await db.query(
      'permisos',
      where: 'rol = ? AND modulo = ?',
      whereArgs: [rol, actualizado.modulo],
      limit: 1,
    );

    if (existentes.isEmpty) {
      final id = await db.insert(
        'permisos',
        actualizado.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      actualizado.id = id;
    } else {
      actualizado.id = (existentes.first['id'] as num?)?.toInt();
      await db.update(
        'permisos',
        actualizado.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [actualizado.id],
      );
    }

    _cache.putIfAbsent(rol, () => {});
    _cache[rol]![actualizado.modulo] = actualizado;
  }

  /// Guarda un lote y registra en auditoría solo los módulos que cambiaron.
  Future<int> guardarLoteConAuditoria(
    Map<String, List<Permiso>> porRol,
  ) async {
    _requiereAdministrador();
    final cambios = <Map<String, dynamic>>[];

    for (final entry in porRol.entries) {
      final rol = _normalizarRol(entry.key);
      final anteriores = await obtenerPorRol(rol);
      final mapaAnt = {
        for (final p in anteriores) p.modulo: p,
      };

      for (final permiso in entry.value) {
        final protegido = _protegerAdmin(permiso);
        final antes = mapaAnt[protegido.modulo];
        final cambio = antes == null || _firma(antes) != _firma(protegido);
        if (cambio) {
          cambios.add({
            'rol': rol,
            'modulo': protegido.modulo,
            'antes': antes == null
                ? null
                : {
                    'ver': antes.puedeVer,
                    'crear': antes.puedeCrear,
                    'editar': antes.puedeEditar,
                    'eliminar': antes.puedeEliminar,
                  },
            'despues': {
              'ver': protegido.puedeVer,
              'crear': protegido.puedeCrear,
              'editar': protegido.puedeEditar,
              'eliminar': protegido.puedeEliminar,
            },
          });
        }
        await actualizar(protegido);
      }
    }

    await cargar();

    if (cambios.isNotEmpty) {
      await AuthService.instance.registrarCambio(
        'MODIFICAR_PERMISOS',
        'permisos',
        'Actualización de permisos (${cambios.length} cambio(s))',
        valorNuevo: jsonEncode({'cambios': cambios}),
      );
    }

    return cambios.length;
  }
}
