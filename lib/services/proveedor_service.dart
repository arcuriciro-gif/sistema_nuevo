import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_background.dart';
import '../database/database_helper.dart';
import '../models/proveedor.dart';
import 'auth_service.dart';

class ProveedorService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  String _snapshot(Proveedor proveedor) {
    return jsonEncode({
      'id': proveedor.id,
      'syncId': proveedor.syncId,
      'nombre': proveedor.nombre,
      'contacto': proveedor.contacto,
      'telefono': proveedor.telefono,
      'email': proveedor.email,
      'cuit': proveedor.cuit,
      'activo': proveedor.activo,
    });
  }

  Proveedor _conSyncId(Proveedor proveedor) {
    if (proveedor.syncId.isNotEmpty) return proveedor;
    return proveedor.copyWith(syncId: const Uuid().v4());
  }

  Future<int> insertar(Proveedor proveedor) async {
    AuthorizationService.instance.require(
      AuthModules.proveedores,
      AuthzAction.crear,
      operacion: 'crear proveedor',
    );
    final db = await _dbHelper.database;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final creado = _conSyncId(proveedor.copyWith(
      fechaCreacion: proveedor.fechaCreacion ?? DateTime.now(),
      actualizadoEn: ahora,
    ));

    final id = await db.insert(
      'proveedores',
      creado.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await AuthService.instance.registrarCambio(
      'ALTA_PROVEEDOR',
      'proveedores',
      'Nuevo proveedor: ${creado.nombre}',
      valorNuevo: _snapshot(creado.copyWith(id: id)),
    );
    syncInBackground(FirestoreSyncService.instance.subirProveedor(id), tag: 'subirProveedor');
    DataRefreshHub.instance.notifyTodo();

    return id;
  }

  Future<int> actualizar(Proveedor proveedor) async {
    AuthorizationService.instance.require(
      AuthModules.proveedores,
      AuthzAction.editar,
      operacion: 'editar proveedor',
    );
    final db = await _dbHelper.database;
    final anterior = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [proveedor.id],
      limit: 1,
    );
    final proveedorAnterior =
        anterior.isNotEmpty ? Proveedor.fromMap(anterior.first) : null;

    final ahora = DateTime.now().toUtc().toIso8601String();
    final listo = (proveedor.syncId.isNotEmpty
            ? proveedor
            : _conSyncId(
                proveedor.copyWith(syncId: proveedorAnterior?.syncId ?? ''),
              ))
        .copyWith(actualizadoEn: ahora);

    final result = await db.update(
      'proveedores',
      listo.toMap(),
      where: 'id = ?',
      whereArgs: [listo.id],
    );

    await AuthService.instance.registrarCambio(
      'MODIFICACION_PROVEEDOR',
      'proveedores',
      'Proveedor actualizado: ${listo.nombre}',
      valorAnterior:
          proveedorAnterior != null ? _snapshot(proveedorAnterior) : null,
      valorNuevo: _snapshot(listo),
    );
    if (listo.id != null) {
      syncInBackground(FirestoreSyncService.instance.subirProveedor(listo.id!), tag: 'subirProveedor');
    }
    DataRefreshHub.instance.notifyTodo();

    return result;
  }

  Future<int> eliminar(int id) async {
    AuthorizationService.instance.require(
      'proveedores',
      AuthzAction.eliminar,
      operacion: 'eliminar proveedor',
    );
    final db = await _dbHelper.database;
    final anterior = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final proveedor =
        anterior.isNotEmpty ? Proveedor.fromMap(anterior.first) : null;

    if (proveedor != null) {
      await AuthService.instance.registrarCambio(
        'BAJA_PROVEEDOR',
        'proveedores',
        'Proveedor eliminado: ${proveedor.nombre}',
        valorAnterior: _snapshot(proveedor),
      );
      // Capacidad 7: encolar tombstone antes del hard-delete local.
      final syncId = proveedor.syncId.trim();
      if (syncId.isNotEmpty) {
        await FirestoreSyncService.instance
            .eliminarProveedorRemoto(syncId, localId: id);
      }
    }

    final result = await db.delete(
      'proveedores',
      where: 'id = ?',
      whereArgs: [id],
    );
    DataRefreshHub.instance.notifyTodo();

    return result;
  }

  Future<Proveedor?> obtenerPorId(int id) async {
    final db = await _dbHelper.database;
    final resultado = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Proveedor.fromMap(resultado.first);
  }

  Future<List<Proveedor>> obtenerTodos() async {
    final db = await _dbHelper.database;
    final resultado = await db.query(
      'proveedores',
      where: 'activo = 1',
      orderBy: 'nombre',
    );

    return resultado.map((e) => Proveedor.fromMap(e)).toList();
  }

  Future<int> cantidad() async {
    final db = await _dbHelper.database;
    final resultado = await db.rawQuery('SELECT COUNT(*) total FROM proveedores');
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<void> cargarProveedoresIniciales() async {
    if (await cantidad() > 0) {
      return;
    }

    final proveedores = [
      'Bisso',
      'Arola',
      'Washington',
      'Fana',
      'Tapper',
      'Cuero Sur',
      'Mercado Libre',
    ];

    for (final nombre in proveedores) {
      await insertar(
        Proveedor(
          nombre: nombre,
          telefono: '',
          email: '',
          observaciones: '',
        ),
      );
    }
  }
}
