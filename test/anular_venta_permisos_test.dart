import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/security/authorization_service.dart';
import 'package:sistema_nuevo/models/permiso.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/permisos_service.dart';

void main() {
  group('Anular venta — permisos', () {
    tearDown(() {
      AuthService.instance.currentUser = null;
      PermisosService.instance.clearCacheForTests();
    });

    test('módulo "ventas" no existe; el correcto es remitos', () {
      AuthService.instance.currentUser = Usuario(
        id: 2,
        nombre: 'Encargado',
        usuario: 'enc',
        password: 'x',
        rol: 'encargado',
        activo: true,
      );
      PermisosService.instance.seedCacheForTests({
        'supervisor': {
          'remitos': Permiso(
            rol: 'supervisor',
            modulo: 'remitos',
            puedeVer: true,
            puedeCrear: true,
            puedeEditar: true,
            puedeEliminar: false,
          ),
        },
      });

      expect(
        AuthorizationService.instance.puede('ventas', AuthzAction.anular),
        isFalse,
      );
      expect(
        AuthorizationService.instance.puede(
          AuthModules.remitos,
          AuthzAction.anular,
        ),
        isTrue,
      );
    });

    test('admin puede anular', () {
      AuthService.instance.currentUser = Usuario(
        id: 1,
        nombre: 'Admin',
        usuario: 'admin',
        password: 'x',
        rol: 'admin',
        activo: true,
      );
      expect(
        AuthorizationService.instance.puede(
          AuthModules.remitos,
          AuthzAction.anular,
        ),
        isTrue,
      );
    });
  });
}
