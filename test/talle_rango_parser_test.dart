import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/services/talle_rango_parser.dart';

void main() {
  group('TalleRangoParser.parsearLineaProveedor', () {
    test('rango AL con precio', () {
      final r = TalleRangoParser.parsearLineaProveedor(
        'PAPI FEBO BLANCA 39 AL 42 \$10000',
      );
      expect(r, isNotNull);
      expect(r!.baseNombre, 'PAPI FEBO BLANCA');
      expect(r.talleDesde, 39);
      expect(r.talleHasta, 42);
      expect(r.costo, 10000);
      expect(r.contieneTalle(41), isTrue);
      expect(r.contieneTalle(43), isFalse);
    });

    test('rango con guion y precio separado', () {
      final r = TalleRangoParser.parsearLineaProveedor(
        'PAPI FEBO BLANCA 43-45 11000',
      );
      expect(r, isNotNull);
      expect(r!.talleDesde, 43);
      expect(r.talleHasta, 45);
      expect(r.costo, 11000);
      expect(r.contieneTalle(43), isTrue);
      expect(r.contieneTalle(45), isTrue);
      expect(r.contieneTalle(42), isFalse);
    });

    test('talle unico sin confundir con precio', () {
      final r = TalleRangoParser.parsearLineaProveedor('PAPI FEBO BLANCA 41');
      expect(r, isNotNull);
      expect(r!.talleDesde, 41);
      expect(r.talleHasta, 41);
      expect(r.costo, isNull);
    });

    test('talle unico con precio', () {
      final r = TalleRangoParser.parsearLineaProveedor(
        'PAPI FEBO BLANCA 41 \$15000',
      );
      expect(r, isNotNull);
      expect(r!.talleDesde, 41);
      expect(r.costo, 15000);
    });
  });

  group('TalleRangoParser.parsearProducto', () {
    test('extrae talle del final de descripcion', () {
      final p = TalleRangoParser.parsearProducto(
        descripcion: 'PAPI FEBO BLANCA 41',
      );
      expect(p.baseNombre, 'PAPI FEBO BLANCA');
      expect(p.talle, 41);
    });

    test('usa campo talle si existe', () {
      final p = TalleRangoParser.parsearProducto(
        descripcion: 'PAPI FEBO BLANCA 41',
        talleCampo: '41',
      );
      expect(p.talle, 41);
      expect(p.baseNombre, 'PAPI FEBO BLANCA');
    });
  });

  test('match producto 41 dentro de rango 39-42', () {
    final linea = TalleRangoParser.parsearLineaProveedor(
      'PAPI FEBO BLANCA 39 AL 42 \$10000',
    )!;
    final prod = TalleRangoParser.parsearProducto(
      descripcion: 'PAPI FEBO BLANCA 41',
    );
    expect(prod.baseNombre, linea.baseNombre);
    expect(linea.contieneTalle(prod.talle!), isTrue);
  });
}
