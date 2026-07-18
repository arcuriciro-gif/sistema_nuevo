import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/services/proveedor_pdf_service.dart';

void main() {
  final pdfPath = 'test/fixtures/cuero_sur_presupuesto.pdf';

  test('extrae y parsea presupuesto Cuero Sur', () async {
    final file = File(pdfPath);
    expect(file.existsSync(), isTrue, reason: 'PDF de prueba ausente en fixtures');

    final svc = ProveedorPdfService();
    final r = svc.leerBytes(Uint8List.fromList(await file.readAsBytes()));

    expect(r.texto.toUpperCase(), contains('PICTO'));
    expect(r.productos.length, greaterThanOrEqualTo(30));

    final cueroMarron = r.productos.where(
      (p) => p.codigo.toUpperCase() == 'PIGM500',
    );
    expect(cueroMarron, isNotEmpty);
    expect(cueroMarron.first.costo, closeTo(11357.33, 0.01));
    expect(
      cueroMarron.first.descripcion.toUpperCase(),
      contains('CUERO'),
    );
    expect(
      cueroMarron.first.descripcion.toUpperCase(),
      contains('MARRON'),
    );

    final terna = r.productos
        .where((p) => p.descripcion.toUpperCase().contains('TERNA NEGRA'))
        .toList();
    expect(terna.length, greaterThanOrEqualTo(3));
    expect(terna.every((p) => p.costo > 1000), isTrue);
  });

  test('parsea línea suelta del presupuesto', () {
    const texto = '''
COD. CANT. ARTICULO PRECIO TOTAL UNI.
34.071,99 PIGM500 11.357,33 3 C/U PICTO CUERO 500CC MARRON
22.714,66 PIGN500 11.357,33 2 C/U PICTO CUERO 500CC NEG
3.048,30 4225.140 1.524,15 2 PAR par TERNA NEGRA 40
TOTAL 573.923,46
''';
    final r = ProveedorPdfService().parsearLineasPresupuesto(texto);
    expect(r.productos.length, 3);
    expect(r.productos[0].codigo, 'PIGM500');
    expect(r.productos[1].codigo, 'PIGN500');
    expect(r.productos[2].descripcion.toUpperCase(), contains('TERNA NEGRA'));
    expect(r.productos[2].descripcion.toUpperCase(), isNot(contains('PAR PAR')));
  });
}
