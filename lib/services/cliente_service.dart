import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
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
    final db = await dbHelper.database;
    final listo = _conSyncId(cliente);
    final id = await db.insert('clientes', listo.toMap());
    await AuthService.instance.registrarCambio(
      'ALTA_CLIENTE',
      'clientes',
      'Nuevo cliente: ${listo.nombreCompleto}',
      valorNuevo: _snapshot(listo.copyWith(id: id)),
    );
    await FirestoreSyncService.instance.subirCliente(id);
    DataRefreshHub.instance.notifyTodo();
    return id;
  }

  Future<int> actualizar(Cliente cliente) async {
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

    final result = await db.update(
      'clientes',
      listo.toMap(),
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
      await FirestoreSyncService.instance.subirCliente(listo.id!);
    }
    DataRefreshHub.instance.notifyTodo();
    return result;
  }

  Future<int> eliminar(int id) async {
    final db = await dbHelper.database;
    final anterior = await db.query(
      'clientes',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    final cliente = anterior.isNotEmpty ? Cliente.fromMap(anterior.first) : null;

    final result = await db.delete(
      'clientes',
      where: 'id=?',
      whereArgs: [id],
    );

    if (cliente != null) {
      await AuthService.instance.registrarCambio(
        'BAJA_CLIENTE',
        'clientes',
        'Cliente eliminado: ${cliente.nombreCompleto}',
        valorAnterior: _snapshot(cliente),
      );
      await FirestoreSyncService.instance.eliminarClienteRemoto(cliente.syncId);
    }
    DataRefreshHub.instance.notifyTodo();

    return result;
  }

  Future<List<Cliente>> obtenerTodos() async {
    final db = await dbHelper.database;
    final resultado = await db.query('clientes', orderBy: 'nombre');
    return resultado.map((e) => Cliente.fromMap(e)).toList();
  }

  Future<Cliente?> buscarPorCuit(String cuit) async {
    final limpio = cuit.trim();
    if (limpio.isEmpty) return null;
    final db = await dbHelper.database;
    final rows = await db.query(
      'clientes',
      where: 'cuit = ?',
      whereArgs: [limpio],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Cliente.fromMap(rows.first);
  }

  Future<Cliente?> buscarPorNombreApellido(String nombre, String apellido) async {
    final n = nombre.trim();
    if (n.isEmpty) return null;
    final db = await dbHelper.database;
    final rows = await db.query(
      'clientes',
      where: 'nombre = ? AND apellido = ?',
      whereArgs: [n, apellido.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Cliente.fromMap(rows.first);
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
