import 'package:sqflite/sqflite.dart';

import '../core/auth/rol_util.dart';
import '../database/database_helper.dart';
import '../models/permiso.dart';

class PermisosService {
  static final PermisosService instance = PermisosService._();
  PermisosService._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Map<String, Map<String, Permiso>> _cache = {};

  String _normalizarRol(String rol) => RolUtil.clavePermisos(rol);

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
    // El administrador siempre ve todo (evita quedar bloqueado si la matriz
    // de permisos está incompleta o llegó mal desde otro dispositivo).
    if (RolUtil.esAdministrador(rol)) return true;
    return _buscar(rol, modulo)?.puedeVer ?? false;
  }

  bool puedeCrear(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol)) return true;
    return _buscar(rol, modulo)?.puedeCrear ?? false;
  }

  bool puedeEditar(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol)) return true;
    return _buscar(rol, modulo)?.puedeEditar ?? false;
  }

  bool puedeEliminar(String rol, String modulo) {
    if (RolUtil.esAdministrador(rol)) return true;
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

  Future<void> actualizar(Permiso permiso) async {
    final db = await _dbHelper.database;
    final rol = _normalizarRol(permiso.rol);
    final actualizado = Permiso(
      id: permiso.id,
      rol: rol,
      modulo: permiso.modulo,
      puedeVer: permiso.puedeVer,
      puedeCrear: permiso.puedeCrear,
      puedeEditar: permiso.puedeEditar,
      puedeEliminar: permiso.puedeEliminar,
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

  /// Reemplaza/mergea la matriz local con la lista remota (Firestore).
  Future<void> aplicarDesdeRemoto(List<Map<String, dynamic>> remotos) async {
    if (remotos.isEmpty) return;
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final raw in remotos) {
      final permiso = Permiso.fromMap(raw);
      if (permiso.rol.isEmpty || permiso.modulo.isEmpty) continue;
      final rol = _normalizarRol(permiso.rol);
      final existentes = await db.query(
        'permisos',
        where: 'rol = ? AND modulo = ?',
        whereArgs: [rol, permiso.modulo],
        limit: 1,
      );
      final data = permiso.toMap()..remove('id');
      data['rol'] = rol;
      if (existentes.isEmpty) {
        batch.insert('permisos', data);
      } else {
        batch.update(
          'permisos',
          data,
          where: 'id = ?',
          whereArgs: [existentes.first['id']],
        );
      }
    }
    await batch.commit(noResult: true);
    await cargar();
  }

  Future<List<Map<String, dynamic>>> exportarParaFirestore() async {
    await cargar();
    final out = <Map<String, dynamic>>[];
    for (final porModulo in _cache.values) {
      for (final p in porModulo.values) {
        out.add(p.toFirestore());
      }
    }
    return out;
  }
}
