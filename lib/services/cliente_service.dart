import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_background.dart';
import '../database/database_helper.dart';
import '../models/cliente.dart';
import 'auth_service.dart';

class ClienteService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  String _snapshot(Cliente cliente) {
    return jsonEncode({
      'id': cliente.id,
      'syncId': cliente.syncId,
      'nombre': cliente.nombre,
      'apellido': cliente.apellido,
      'telefono': cliente.telefono,
      'email': cliente.email,
      'direccion': cliente.direccion,
      'cuit': cliente.cuit,
      'saldo': cliente.saldo,
    });
  }

  Cliente _conSyncId(Cliente cliente) {
    if (cliente.syncId.isNotEmpty) return cliente;
    return cliente.copyWith(syncId: const Uuid().v4());
  }

  Future<int> insertar(Cliente cliente) async {
    AuthorizationService.instance.require(
      AuthModules.clientes,
      AuthzAction.crear,
      operacion: 'crear cliente',
    );
    final db = await dbHelper.database;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final listo = _conSyncId(cliente);
    final map = listo.toMap()..['actualizadoEn'] = ahora;
    final id = await db.insert('clientes', map);
    await AuthService.instance.registrarCambio(
      'ALTA_CLIENTE',
      'clientes',
      'Nuevo cliente: ${listo.nombreCompleto}',
      valorNuevo: _snapshot(listo.copyWith(id: id)),
    );
    // Offline: no bloquear el alta esperando Firestore (queda en outbox).
    syncInBackground(
      FirestoreSyncService.instance.subirCliente(id, forzar: true),
      tag: 'subirCliente',
    );
    DataRefreshHub.instance.notifyTodo();
    return id;
  }

  Future<int> actualizar(Cliente cliente) async {
    AuthorizationService.instance.require(
      AuthModules.clientes,
      AuthzAction.editar,
      operacion: 'editar cliente',
    );
    final db = await dbHelper.database;
    final anterior = await db.query(
      'clientes',
      where: 'id=?',
      whereArgs: [cliente.id],
      limit: 1,
    );
    final clienteAnterior =
        anterior.isNotEmpty ? Cliente.fromMap(anterior.first) : null;

    final listo = cliente.syncId.isNotEmpty
        ? cliente
        : _conSyncId(
            cliente.copyWith(syncId: clienteAnterior?.syncId ?? ''),
          );

    final ahora = DateTime.now().toUtc().toIso8601String();
    final result = await db.update(
      'clientes',
      listo.toMap()..['actualizadoEn'] = ahora,
      where: 'id=?',
      whereArgs: [listo.id],
    );

    await AuthService.instance.registrarCambio(
      'MODIFICACION_CLIENTE',
      'clientes',
      'Cliente actualizado: ${listo.nombreCompleto}',
      valorAnterior:
          clienteAnterior != null ? _snapshot(clienteAnterior) : null,
      valorNuevo: _snapshot(listo),
    );

    if (listo.id != null) {
      syncInBackground(
        FirestoreSyncService.instance.subirCliente(listo.id!, forzar: true),
        tag: 'subirCliente',
      );
    }
    DataRefreshHub.instance.notifyTodo();
    return result;
  }

  Future<int> eliminar(int id) async {
    AuthorizationService.instance.require(
      'clientes',
      AuthzAction.eliminar,
      operacion: 'eliminar cliente',
    );
    final db = await dbHelper.database;
    final anterior = await db.query(
      'clientes',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    final cliente = anterior.isNotEmpty ? Cliente.fromMap(anterior.first) : null;

    if (cliente != null) {
      await AuthService.instance.registrarCambio(
        'BAJA_CLIENTE',
        'clientes',
        'Cliente eliminado: ${cliente.nombreCompleto}',
        valorAnterior: _snapshot(cliente),
      );
      // Capacidad 7: encolar tombstone antes del hard-delete local.
      final syncId = cliente.syncId.trim();
      if (syncId.isNotEmpty) {
        await FirestoreSyncService.instance
            .eliminarClienteRemoto(syncId, localId: id);
      }
    }

    final result = await db.delete(
      'clientes',
      where: 'id=?',
      whereArgs: [id],
    );
    DataRefreshHub.instance.notifyTodo();

    return result;
  }

  Future<List<Cliente>> obtenerTodos() async {
    final db = await dbHelper.database;
    final resultado = await db.query('clientes', orderBy: 'nombre');
    return resultado.map((e) => Cliente.fromMap(e)).toList();
  }

  /// Busca o crea el cliente especial MOSTRADOR para Venta Rápida.
  Future<Cliente> obtenerOCrearMostrador() async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'clientes',
      where: 'nombre = ?',
      whereArgs: ['MOSTRADOR'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Cliente.fromMap(rows.first);
    }
    final id = await insertar(
      Cliente(
        nombre: 'MOSTRADOR',
        telefono: '',
        direccion: '',
        observaciones: 'Cliente mostrador',
      ),
    );
    return (await db.query('clientes', where: 'id=?', whereArgs: [id], limit: 1))
        .map(Cliente.fromMap)
        .first;
  }
}
