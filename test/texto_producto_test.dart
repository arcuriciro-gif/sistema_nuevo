import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/utils/texto_producto.dart';

void main() {
  group('familia hermanos / alias color PDF', () {
    test('NEG se normaliza a negro', () {
      expect(TextoProducto.normalizar('PICTO CUERO 500CC NEG'), contains('negro'));
      expect(
        TextoProducto.coloresEnTexto('PICTO CUERO 500CC NEG'),
        contains('negro'),
      );
    });

    test('clave familia no cruza modelos parecidos', () {
      final cueroNeg =
          TextoProducto.claveFamiliaHermanos('PICTO CUERO 500CC NEGRO');
      final gamuzNeg =
          TextoProducto.claveFamiliaHermanos('PICTO GAMUZ 500CC NEGRO');
      final ternaNeg40 =
          TextoProducto.claveFamiliaHermanos('TERNA NEGRA 40');
      final ternaNeg42 =
          TextoProducto.claveFamiliaHermanos('TERNA NEGRA 42');
      final ternaToalla =
          TextoProducto.claveFamiliaHermanos('TERNA TOALLA 3.5 MM 42');

      expect(cueroNeg, isNot(equals(gamuzNeg)));
      expect(ternaNeg40, equals(ternaNeg42));
      expect(ternaNeg40, isNot(equals(ternaToalla)));
    });
  });

  group('articuloBase / precio único por modelo', () {
    test('quita talle y color del proveedor', () {
      expect(TextoProducto.articuloBase('marilyn 39'), 'marilyn');
      expect(TextoProducto.articuloBase('marilyn'), 'marilyn');
      expect(TextoProducto.articuloBase('Marilyn Negro 39'), 'marilyn');
      expect(TextoProducto.articuloBase('PROFETA SPORT 40'), 'profeta sport');
    });

    test('mismo artículo ignora color/talle locales', () {
      expect(
        TextoProducto.localEsMismoModeloPrecioUnico(
          descripcionProveedor: 'marilyn 39',
          descripcionLocal: 'marilyn',
          modeloLocal: '',
        ),
        isTrue,
      );
      expect(
        TextoProducto.localEsMismoModeloPrecioUnico(
          descripcionProveedor: 'marilyn',
          descripcionLocal: 'marilyn',
          modeloLocal: '',
        ),
        isTrue,
      );
      expect(
        TextoProducto.localEsMismoModeloPrecioUnico(
          descripcionProveedor: 'marilyn',
          descripcionLocal: 'zapatilla',
          modeloLocal: 'marilyn',
        ),
        isTrue,
      );
      expect(
        TextoProducto.localEsMismoModeloPrecioUnico(
          descripcionProveedor: 'marilyn',
          descripcionLocal: 'papi',
          modeloLocal: '',
        ),
        isFalse,
      );
    });

    test('no cruza modelos distintos con nombre parecido', () {
      expect(TextoProducto.mismoArticulo('marilyn', 'marilyn sport'), isFalse);
      expect(TextoProducto.mismoArticulo('papi', 'papi futbol'), isFalse);
      expect(TextoProducto.mismoArticulo('profeta', 'profeta'), isTrue);
    });
  });

  group('Febo rango + color', () {
    test('parsea rango y conserva color en base', () {
      final r = TextoProducto.parsearRangoTalle('papi blanco 39-42');
      expect(r.desde, 39);
      expect(r.hasta, 42);
      expect(r.base.contains('blanco'), isTrue);
      expect(r.base.contains('papi'), isTrue);
    });

    test('filtra color del proveedor', () {
      expect(
        TextoProducto.localCoincideColorProveedor(
          descripcionLocal: 'papi',
          colorLocal: 'blanco',
          textoProveedorSinTalle: 'papi blanco',
        ),
        isTrue,
      );
      expect(
        TextoProducto.localCoincideColorProveedor(
          descripcionLocal: 'papi',
          colorLocal: 'negro',
          textoProveedorSinTalle: 'papi blanco',
        ),
        isFalse,
      );
    });

    test('talle local dentro del rango', () {
      expect(
        TextoProducto.localEnRangoProveedor(
          descripcionLocal: 'papi',
          colorLocal: 'blanco',
          talleLocal: '40',
          desde: 39,
          hasta: 42,
        ),
        isTrue,
      );
      expect(
        TextoProducto.localEnRangoProveedor(
          descripcionLocal: 'papi',
          colorLocal: 'blanco',
          talleLocal: '43',
          desde: 39,
          hasta: 42,
        ),
        isFalse,
      );
    });
  });

  group('proveedorCompatible', () {
    test('vacío no bloquea; distinto proveedor sí', () {
      expect(TextoProducto.proveedorCompatible('Leal', ''), isTrue);
      expect(TextoProducto.proveedorCompatible('Leal', 'Leal'), isTrue);
      expect(TextoProducto.proveedorCompatible('Leal', 'Febo'), isFalse);
      expect(TextoProducto.proveedorCompatible('', 'Febo'), isTrue);
    });
  });
}
