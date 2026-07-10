import 'dart:convert';

import '../database/database_helper.dart';
import '../models/cliente.dart';
import 'auth_service.dart';

class ClienteService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  String _snapshot(Cliente cliente) {
    return jsonEncode({
      'id': cliente.id,
      'nombre': cliente.nombre,
      'apellido': cliente.apellido,
      'telefono': cliente.telefono,
      'email': cliente.email,
      'direccion': cliente.direccion,
      'cuit': cliente.cuit,
      'saldo': cliente.saldo,
    });
  }

  Future<int> insertar(Cliente cliente) async {
    final db = await dbHelper.database;
    final id = await db.insert('clientes', cliente.toMap());
    await AuthService.instance.registrarCambio(
      'ALTA_CLIENTE',
      'clientes',
      'Nuevo cliente: ${cliente.nombreCompleto}',
      valorNuevo: _snapshot(cliente.copyWith(id: id)),
    );
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
    final clienteAnterior = anterior.isNotEmpty ? Cliente.fromMap(anterior.first) : null;

    final result = await db.update(
      'clientes',
      cliente.toMap(),
      where: 'id=?',
      whereArgs: [cliente.id],
    );

    await AuthService.instance.registrarCambio(
      'MODIFICACION_CLIENTE',
      'clientes',
      'Cliente actualizado: ${cliente.nombreCompleto}',
      valorAnterior: clienteAnterior != null ? _snapshot(clienteAnterior) : null,
      valorNuevo: _snapshot(cliente),
    );

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
    }

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
      where: 'UPPER(nombre) = ?',
      whereArgs: ['MOSTRADOR'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Cliente.fromMap(rows.first);
    }
    // Crear cliente MOSTRADOR
    final mostrador = Cliente(
      nombre: 'MOSTRADOR',
      telefono: '',
      direccion: '',
      observaciones: 'Cliente especial para ventas rápidas en mostrador',
    );
    final id = await insertar(mostrador);
    return mostrador.copyWith(id: id);
  }
}
