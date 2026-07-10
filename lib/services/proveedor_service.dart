import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/proveedor.dart';
import 'auth_service.dart';

class ProveedorService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  String _snapshot(Proveedor proveedor) {
    return jsonEncode({
      'id': proveedor.id,
      'nombre': proveedor.nombre,
      'contacto': proveedor.contacto,
      'telefono': proveedor.telefono,
      'email': proveedor.email,
      'cuit': proveedor.cuit,
      'activo': proveedor.activo,
    });
  }

  Future<int> insertar(Proveedor proveedor) async {
    final db = await _dbHelper.database;
    final creado = proveedor.copyWith(
      fechaCreacion: proveedor.fechaCreacion ?? DateTime.now(),
    );

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

    return id;
  }

  Future<int> actualizar(Proveedor proveedor) async {
    final db = await _dbHelper.database;
    final anterior = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [proveedor.id],
      limit: 1,
    );
    final proveedorAnterior = anterior.isNotEmpty ? Proveedor.fromMap(anterior.first) : null;

    final result = await db.update(
      'proveedores',
      proveedor.toMap(),
      where: 'id = ?',
      whereArgs: [proveedor.id],
    );

    await AuthService.instance.registrarCambio(
      'MODIFICACION_PROVEEDOR',
      'proveedores',
      'Proveedor actualizado: ${proveedor.nombre}',
      valorAnterior: proveedorAnterior != null ? _snapshot(proveedorAnterior) : null,
      valorNuevo: _snapshot(proveedor),
    );

    return result;
  }

  Future<int> eliminar(int id) async {
    final db = await _dbHelper.database;
    final anterior = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final proveedor = anterior.isNotEmpty ? Proveedor.fromMap(anterior.first) : null;

    final result = await db.delete(
      'proveedores',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (proveedor != null) {
      await AuthService.instance.registrarCambio(
        'BAJA_PROVEEDOR',
        'proveedores',
        'Proveedor eliminado: ${proveedor.nombre}',
        valorAnterior: _snapshot(proveedor),
      );
    }

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
