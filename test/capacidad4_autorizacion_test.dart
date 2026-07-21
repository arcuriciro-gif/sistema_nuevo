import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/security/authorization_service.dart';
import 'package:sistema_nuevo/models/permiso.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/permisos_service.dart';

void main() {
  tearDown(() {
    AuthService.instance.currentUser = null;
    PermisosService.instance.clearCacheForTests();
  });

  void setUser(String rol) {
    AuthService.instance.currentUser = Usuario(
      nombre: 'Test',
      usuario: 'test_$rol',
      password: 'x',
      rol: rol,
    );
  }

  void seedEmpleadoSinCrearProductos() {
    PermisosService.instance.seedCacheForTests({
      'empleado': {
        'productos': Permiso(
          rol: 'empleado',
          modulo: 'productos',
          puedeVer: true,
          puedeCrear: false,
          puedeEditar: true,
          puedeEliminar: false,
        ),
        'remitos': Permiso(
          rol: 'empleado',
          modulo: 'remitos',
          puedeVer: true,
          puedeCrear: true,
          puedeEditar: true,
          puedeEliminar: false,
        ),
        'stock': Permiso(
          rol: 'empleado',
          modulo: 'stock',
          puedeVer: true,
          puedeCrear: false,
          puedeEditar: false,
          puedeEliminar: false,
        ),
      },
    });
  }

  group('Capacidad 4 — AuthorizationService', () {
    test('sin sesión no puede nada', () {
      expect(
        AuthorizationService.instance.puede(AuthModules.productos, AuthzAction.ver),
        isFalse,
      );
    });

    test('admin puede crear/editar/eliminar/anular', () {
      setUser('admin');
      expect(
        AuthorizationService.instance.puede(AuthModules.productos, AuthzAction.crear),
        isTrue,
      );
      expect(
        AuthorizationService.instance.puede(AuthModules.remitos, AuthzAction.anular),
        isTrue,
      );
      expect(() {
        AuthorizationService.instance.require(
          AuthModules.stock,
          AuthzAction.editar,
          operacion: 'ajustar stock',
        );
      }, returnsNormally);
    });

    test('solo_lectura solo puede ver', () {
      setUser('solo_lectura');
      expect(
        AuthorizationService.instance.puede(AuthModules.productos, AuthzAction.ver),
        isTrue,
      );
      expect(
        AuthorizationService.instance.puede(AuthModules.productos, AuthzAction.crear),
        isFalse,
      );
      expect(
        AuthorizationService.instance.puede(AuthModules.stock, AuthzAction.editar),
        isFalse,
      );
      expect(
        () => AuthorizationService.instance.require(
          AuthModules.productos,
          AuthzAction.crear,
          operacion: 'crear producto',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No autorizado'),
          ),
        ),
      );
      expect(
        () => AuthorizationService.instance.require(
          AuthModules.remitos,
          AuthzAction.crear,
          operacion: 'crear remito',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => AuthorizationService.instance.require(
          AuthModules.stock,
          AuthzAction.editar,
          operacion: 'ajustar stock',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('empleado respeta matriz (sin crear productos / sin editar stock)', () {
      setUser('empleado');
      seedEmpleadoSinCrearProductos();

      expect(
        AuthorizationService.instance.puede(AuthModules.productos, AuthzAction.ver),
        isTrue,
      );
      expect(
        AuthorizationService.instance.puede(AuthModules.productos, AuthzAction.crear),
        isFalse,
      );
      expect(
        AuthorizationService.instance.puede(AuthModules.remitos, AuthzAction.crear),
        isTrue,
      );
      expect(
        AuthorizationService.instance.puede(AuthModules.stock, AuthzAction.editar),
        isFalse,
      );

      expect(
        () => AuthorizationService.instance.require(
          AuthModules.productos,
          AuthzAction.crear,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => AuthorizationService.instance.require(
          AuthModules.remitos,
          AuthzAction.crear,
        ),
        returnsNormally,
      );
      expect(
        () => AuthorizationService.instance.require(
          AuthModules.stock,
          AuthzAction.editar,
          operacion: 'ajustar stock',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('requireAdmin falla para no admin', () {
      setUser('encargado');
      expect(
        () => AuthorizationService.instance.requireAdmin(operacion: 'restaurar backup'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('administrador'),
          ),
        ),
      );
      setUser('admin');
      expect(
        () => AuthorizationService.instance.requireAdmin(operacion: 'restaurar backup'),
        returnsNormally,
      );
    });

    test('módulos AuthModules son estables', () {
      expect(AuthModules.productos, 'productos');
      expect(AuthModules.remitos, 'remitos');
      expect(AuthModules.stock, 'stock');
      expect(AuthModules.backup, 'backup');
      expect(AuthModules.configuracion, 'configuracion');
    });
  });
}
