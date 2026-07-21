import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/auth/rol_util.dart';

void main() {
  test('RolUtil reconoce administrador', () {
    expect(RolUtil.normalizar('admin'), RolUtil.administrador);
    expect(RolUtil.normalizar('Administrador'), RolUtil.administrador);
  });

  test('mensaje de cuenta nube existente se puede detectar', () {
    const msg =
        'CUENTA_NUBE_EXISTE: La cuenta ya existe en la nube (creada en la PC).';
    expect(msg.startsWith('CUENTA_NUBE_EXISTE:'), isTrue);
    expect(
      msg.replaceFirst('CUENTA_NUBE_EXISTE: ', ''),
      startsWith('La cuenta ya existe'),
    );
  });
}
