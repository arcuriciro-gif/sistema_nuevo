import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/auth/rol_util.dart';
import 'package:sistema_nuevo/core/auth/usuario_auth_email.dart';
import 'package:sistema_nuevo/core/config/backend_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('alta por admin: email sintético si no hay Gmail', () async {
    await BackendConfigService.instance.cargar();
    await BackendConfigService.instance.setTenantId('tata_stock');

    final email = UsuarioAuthEmail.paraUsuario('Francisco');
    expect(email, 'francisco@tata-stock.tatastock.app');
    expect(UsuarioAuthEmail.esEmailReal(email), isFalse);
  });

  test('roles asignables incluyen solo lectura', () {
    expect(RolUtil.rolesAsignables, contains('solo_lectura'));
    expect(RolUtil.etiqueta('solo_lectura'), 'Solo lectura');
    expect(RolUtil.etiqueta('admin'), 'Administrador');
  });
}
