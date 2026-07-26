import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/integrity/integrity_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/cliente.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/cliente_service.dart';
import 'package:sistema_nuevo/services/cuenta_corriente_service.dart';

/// Evidencia C7: CC se alinea con saldos de docs (como tras apply remoto).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await IntegrityPolicy.instance.cargar();
    tmp = await Directory.systemTemp.createTemp('cc_remoto_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 'test.db'),
    );
    DomainBootstrap.resetForTests();
    DomainBootstrap.ensureInitialized();
    AuthService.instance.currentUser = Usuario(
      id: 1,
      nombre: 'Admin',
      usuario: 'admin',
      password: 'x',
      rol: 'admin',
      activo: true,
      email: 'admin@test.local',
    );
  });

  tearDown(() async {
    DomainBootstrap.resetForTests();
    AuthService.instance.currentUser = null;
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('recalcularSaldoCliente refleja remitos/ventas no anulados', () async {
    final cid = await ClienteService().insertar(
      Cliente(
        nombre: 'CC Test',
        apellido: '',
        telefono: '',
        email: '',
        direccion: '',
        cuit: '',
        observaciones: '',
        saldo: 0,
        limiteCuenta: 0,
      ),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('remitos', {
      'numero': 'R-CC-1',
      'fecha': DateTime.now().toIso8601String(),
      'clienteId': cid,
      'total': 500,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 500,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    await db.insert('ventas', {
      'tipo': 'factura_b',
      'numero': 'B-CC-1',
      'clienteId': cid,
      'fecha': DateTime.now().toIso8601String(),
      'total': 200,
      'descuento': 0,
      'iva': 0,
      'estado': 'confirmada',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 200,
      'estadoAfip': 'no_aplica',
      'cae': '',
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });

    await CuentaCorrienteService().recalcularSaldoCliente(cid);
    final rows = await db.query(
      'clientes',
      columns: ['saldo'],
      where: 'id = ?',
      whereArgs: [cid],
    );
    expect((rows.first['saldo'] as num).toDouble(), 700);

    // Anular remito remoto → CC baja.
    await db.update(
      'remitos',
      {'estado': 'anulado', 'saldoPendiente': 0},
      where: 'numero = ?',
      whereArgs: ['R-CC-1'],
    );
    await CuentaCorrienteService().recalcularSaldoCliente(cid);
    final rows2 = await db.query(
      'clientes',
      columns: ['saldo'],
      where: 'id = ?',
      whereArgs: [cid],
    );
    expect((rows2.first['saldo'] as num).toDouble(), 200);
  });
}
