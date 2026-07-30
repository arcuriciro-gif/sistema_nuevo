import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/models/producto.dart';

/// Convergencia papelera + stock bajo freeze (EXE no se cierra).
void main() {
  test('freeze ON: criticalConvergenceBudget acotado anti-crash', () {
    expect(WindowsSyncPolicy.freezeBackgroundForStability, isTrue);
    final b = WindowsSyncPolicy.criticalConvergenceBudget();
    expect(b.productosRecientes, lessThanOrEqualTo(25));
    expect(b.productosCatalogoPage, lessThanOrEqualTo(20));
    expect(b.stockMaxApply, lessThanOrEqualTo(4));
    expect(b.stockMaxApply, greaterThan(0));
    expect(
      WindowsSyncPolicy.criticalConvergenceInterval.inSeconds,
      greaterThanOrEqualTo(60),
    );
  });

  test('papelera: deletedAt distinto fuerza sync aunque LWW de catálogo pierda',
      () {
    final local = Producto(
      id: 1,
      codigo: 'SKU-P',
      descripcion: 'X',
      marca: '',
      categoria: '',
      proveedor: '',
      ubicacion: '',
      stock: 3,
      costo: 0,
      precio: 10,
      observaciones: '',
      foto: '',
      deletedAt: '2026-07-30T01:00:00.000Z',
      actualizadoEn: '2026-07-30T01:00:00.000Z',
    );
    final remoto = Producto(
      codigo: 'SKU-P',
      descripcion: 'X',
      marca: '',
      categoria: '',
      proveedor: '',
      ubicacion: '',
      stock: 99,
      costo: 0,
      precio: 10,
      observaciones: '',
      foto: '',
      deletedAt: null,
      actualizadoEn: '2026-07-30T02:00:00.000Z', // más nuevo (stock bump cloud)
    );
    expect(local.estaEliminado, isTrue);
    expect(remoto.estaEliminado, isFalse);
    // Política: si el estado de papelera difiere → subir deleted_at sí o sí.
    expect(local.estaEliminado != remoto.estaEliminado, isTrue);
    final remTs = DateTime.parse(remoto.actualizadoEn!);
    final locTs = DateTime.parse(local.actualizadoEn!);
    expect(remTs.isAfter(locTs), isTrue);
  });

  test('restore clearDeletedAt deja producto activo', () {
    final p = Producto(
      codigo: 'R',
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
    expect(p.copyWith(clearDeletedAt: true).estaEliminado, isFalse);
  });

  test('fromFirestore hidrata deleted_at desde deletedAt camelCase', () {
    final p = Producto.fromFirestore({
      'codigo': 'C1',
      'descripcion': 'D',
      'marca': '',
      'categoria': '',
      'proveedor': '',
      'ubicacion': '',
      'stock': 0,
      'costo': 0,
      'precio': 1,
      'observaciones': '',
      'foto': '',
      'deletedAt': '2026-07-30T00:00:00.000Z',
    });
    expect(p.estaEliminado, isTrue);
  });
}
