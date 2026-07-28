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
    expect(BackendConfigService.esTenantAutogenerado(generado), isTrue);
    expect(BackendConfigService.instance.empresaConfirmada, isFalse);
    expect(BackendConfigService.instance.riesgoDesyncMultiDispositivo, isTrue);

    await BackendConfigService.instance.setTenantId('tata_stock');
    expect(BackendConfigService.instance.tenantId, 'tata_stock');
    expect(BackendConfigService.instance.isLegacySharedTenant, isTrue);
    expect(BackendConfigService.instance.empresaConfirmada, isTrue);
    expect(BackendConfigService.instance.riesgoDesyncMultiDispositivo, isFalse);

    expect(
      () => BackendConfigService.instance.setTenantId('  '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('unirAEmpresaCompartidaLegada desde t_ auto (campo EXE≠APK)', () async {
    SharedPreferences.setMockInitialValues({
      'backend_tenant_id': 't_736fba5653674850a1d68e77c96728b3',
      'backend_empresa_confirmada': true,
    });
    await BackendConfigService.instance.cargar();
    expect(BackendConfigService.instance.tenantId,
        't_736fba5653674850a1d68e77c96728b3');
    expect(BackendConfigService.instance.riesgoDesyncMultiDispositivo, isTrue);

    final changed =
        await BackendConfigService.instance.unirAEmpresaCompartidaLegada();
    expect(changed, isTrue);
    expect(BackendConfigService.instance.tenantId, 'tata_stock');
    expect(BackendConfigService.instance.riesgoDesyncMultiDispositivo, isFalse);

    final again =
        await BackendConfigService.instance.unirAEmpresaCompartidaLegada();
    expect(again, isFalse);
  });
}
