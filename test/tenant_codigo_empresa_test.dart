import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sistema_nuevo/core/config/backend_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('legacySharedTenantId es tata_stock', () {
    expect(BackendConfigService.legacySharedTenantId, 'tata_stock');
  });

  test('setTenantId persiste y rechaza vacío', () async {
    await BackendConfigService.instance.cargar();
    final generado = BackendConfigService.instance.tenantId;
    expect(generado, isNotEmpty);

    await BackendConfigService.instance.setTenantId('tata_stock');
    expect(BackendConfigService.instance.tenantId, 'tata_stock');
    expect(BackendConfigService.instance.isLegacySharedTenant, isTrue);

    expect(
      () => BackendConfigService.instance.setTenantId('  '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
