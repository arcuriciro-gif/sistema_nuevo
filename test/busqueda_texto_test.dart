import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/utils/busqueda_texto.dart';

void main() {
  test('papi encuentra papifutbol', () {
    expect(
      BusquedaTexto.coincide('papi', ['febo papifutbol goma negro 34']),
      isTrue,
    );
  });

  test('varios tokens AND', () {
    expect(
      BusquedaTexto.coincide(
        'papi negro',
        ['febo papifutbol goma negro 34'],
      ),
      isTrue,
    );
    expect(
      BusquedaTexto.coincide(
        'papi negro 34',
        ['febo papifutbol goma negro 34'],
      ),
      isTrue,
    );
    expect(
      BusquedaTexto.coincide(
        'papi negro 42',
        ['febo papifutbol goma negro 34'],
      ),
      isFalse,
    );
    expect(
      BusquedaTexto.coincide(
        'papi negro 42',
        ['febo papifutbol goma negro 42'],
      ),
      isTrue,
    );
  });

  test('orden de tokens no importa', () {
    expect(
      BusquedaTexto.coincide(
        'negro papi',
        ['febo papifutbol goma negro 34'],
      ),
      isTrue,
    );
  });
}
