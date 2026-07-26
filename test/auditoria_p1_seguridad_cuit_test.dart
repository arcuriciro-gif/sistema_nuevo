import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sistema_nuevo/core/utils/cuit.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/afip_service.dart';
import 'package:sistema_nuevo/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthService.instance.currentUser = Usuario(
      id: 1,
      nombre: 'Admin',
      usuario: 'admin',
      password: 'x',
      rol: 'admin',
      activo: true,
      email: 'a@t.local',
    );
  });

  tearDown(() {
    AuthService.instance.currentUser = null;
  });

  group('CUIT', () {
    test('acepta CUIT válido conocido', () {
      // 20-12345678-6 es un patrón típico; usamos uno con DV correcto.
      expect(Cuit.esValido('20123456786'), isTrue);
    });

    test('rechaza CUIT corto o basura', () {
      expect(Cuit.esValido('20-123'), isFalse);
      expect(Cuit.esValido('abc'), isFalse);
      expect(Cuit.esValido(''), isFalse);
    });

    test('rechaza dígito verificador incorrecto', () {
      expect(Cuit.esValido('20123456780'), isFalse);
    });
  });

  group('Password KDF', () {
    test('hash v2 verifica y no es SHA-256 plano', () {
      final h = AuthService.hashPassword('secreto123');
      expect(h.startsWith('v2\$'), isTrue);
      expect(AuthService.verifyPassword('secreto123', h), isTrue);
      expect(AuthService.verifyPassword('otra', h), isFalse);
    });

    test('acepta hash legado SHA-256 y verify funciona', () {
      // sha256("admin123")
      const legacy =
          '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9';
      expect(AuthService.verifyPassword('admin123', legacy), isTrue);
      expect(AuthService.verifyPassword('otra', legacy), isFalse);
    });
  });

  group('AFIP gate', () {
    test('con AFIP enabled sin certs → ok false sin CAE', () async {
      await AfipConfigService.instance.guardar(
        enabled: true,
        ambiente: 'homo',
        puntoVenta: 1,
        cuitEmisor: '20123456786',
        certPath: '',
        keyPath: '',
      );
      final r = await AfipService.instance.autorizarFactura(
        tipo: 'factura_b',
        numero: 'B-1',
        total: 100,
      );
      expect(r.ok, isFalse);
      expect(r.cae, isNull);
    });
  });
}
