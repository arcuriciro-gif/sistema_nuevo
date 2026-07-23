import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/lista_precio.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/lista_precio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Listas de precios offline', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('listas_off_');
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

    test('crear/editar lista no espera la nube', () async {
      final svc = ListaPrecioService();
      final sw = Stopwatch()..start();
      final id = await svc.insertar(
        ListaPrecio(
          nombre: 'Mayorista OFF',
          porcentaje: 35,
          orden: 10,
          prioridad: 1,
          activa: true,
        ),
      );
      await svc.actualizar(
        ListaPrecio(
          id: id,
          nombre: 'Mayorista OFF',
          porcentaje: 40,
          orden: 10,
          prioridad: 1,
          activa: true,
        ),
      );
      sw.stop();

      expect(id, greaterThan(0));
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));

      final listas = await svc.obtenerTodas();
      final m = listas.firstWhere((l) => l.id == id);
      expect(m.porcentaje, 40);

      // La marca pendiente se setea en segundo plano.
      var pendiente = false;
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        final prefs = await SharedPreferences.getInstance();
        pendiente = prefs.getBool('sync_config_listas_pendiente') ?? false;
        if (pendiente) break;
      }
      expect(pendiente, isTrue);
    });
  });
}
