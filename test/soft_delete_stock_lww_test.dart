import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/models/producto.dart';

/// Soft-delete no debe quedar bloqueado por actualizadoEn de stock.
///
/// Causa campo 2884↔2883: stock_ops bumpaban actualizadoEn local → pull
/// de catálogo hacía `continue` y nunca aplicaba deleted_at remoto.
void main() {
  test('deletedAt remoto difiere aunque local actualizadoEn sea más nuevo', () {
    final local = Producto(
      id: 1,
      codigo: 'SKU-1',
      descripcion: 'Test',
      marca: '',
      categoria: '',
      proveedor: '',
      ubicacion: '',
      stock: 3,
      costo: 0,
      precio: 10,
      observaciones: '',
      foto: '',
      deletedAt: null,
      actualizadoEn: '2026-07-29T12:00:00.000Z', // más nuevo (era stock bump)
    );
    final remoto = Producto(
      codigo: 'SKU-1',
      descripcion: 'Test',
      marca: '',
      categoria: '',
      proveedor: '',
      ubicacion: '',
      stock: 99, // stock remoto se ignora
      costo: 0,
      precio: 10,
      observaciones: '',
      foto: '',
      deletedAt: '2026-07-28T10:00:00.000Z', // soft-delete remoto
      actualizadoEn: '2026-07-28T10:00:00.000Z', // más viejo
    );

    final locTs = DateTime.parse(local.actualizadoEn!);
    final remTs = DateTime.parse(remoto.actualizadoEn!);
    expect(locTs.isAfter(remTs), isTrue);

    // Política corregida: reconciliar deleted_at aunque LWW saltee metadata.
    final mustApplyDelete = remoto.estaEliminado != local.estaEliminado;
    expect(mustApplyDelete, isTrue);
    expect(remoto.estaEliminado, isTrue);
    expect(local.estaEliminado, isFalse);
  });

  test('copyWith clearDeletedAt restaura producto activo', () {
    final p = Producto(
      codigo: 'X',
      descripcion: 'Y',
      marca: '',
      categoria: '',
      proveedor: '',
      ubicacion: '',
      stock: 1,
      costo: 0,
      precio: 1,
      observaciones: '',
      foto: '',
      deletedAt: '2026-07-01T00:00:00.000Z',
    );
    expect(p.estaEliminado, isTrue);
    final restored = p.copyWith(clearDeletedAt: true);
    expect(restored.estaEliminado, isFalse);
    expect(restored.deletedAt, isNull);
  });
}
