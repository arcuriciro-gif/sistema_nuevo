import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/auth/rol_util.dart';
import 'package:sistema_nuevo/core/config/backend_config_service.dart';

void main() {
  group('Capacidad 1 — tenant isolation', () {
    test('generarTenantIdNuevo produce id no adivinable', () {
      final a = BackendConfigService.generarTenantIdNuevo();
      final b = BackendConfigService.generarTenantIdNuevo();
      expect(a.startsWith('t_'), isTrue);
      expect(b.startsWith('t_'), isTrue);
      expect(a, isNot(equals(b)));
      expect(a.contains('tata_stock'), isFalse);
      expect(a.length, greaterThanOrEqualTo(20));
    });

    test('legacy shared tenant id es constante explícita', () {
      expect(BackendConfigService.legacySharedTenantId, 'tata_stock');
    });
  });

  group('Capacidad 1 — roles', () {
    test('solo_lectura es asignable y etiquetable', () {
      expect(RolUtil.rolesAsignables, contains('solo_lectura'));
      expect(RolUtil.etiqueta('solo_lectura'), 'Solo lectura');
    });

    test('normalizar no convierte empleado en admin', () {
      expect(RolUtil.normalizar('empleado'), RolUtil.empleado);
      expect(RolUtil.esAdministrador('empleado'), isFalse);
      expect(RolUtil.esAdministrador('admin'), isTrue);
    });
  });
}
