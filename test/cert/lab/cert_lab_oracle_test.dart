@Tags(['cert-lab'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

void main() {
  test('oráculo detecta divergencia de stock con detalle', () {
    final events = [
      CertLabEvent(
        seq: 1,
        at: DateTime.now().toUtc(),
        node: CertLabNodeId.android,
        kind: 'venta',
        entity: CertLabEntity.stock,
        payload: {'codigo': 'pruebq', 'delta': -10},
      ),
    ];
    final win = CertLabSnapshot(
      node: CertLabNodeId.windows,
      at: DateTime.now().toUtc(),
      counts: const {'productos': 1, 'clientes': 0, 'proveedores': 0},
      stockByCodigo: const {'pruebq': 43},
      precioByCodigo: const {'pruebq': 10},
      saldoByCliente: const {},
      docIds: const {},
      stockOpIds: const {},
    );
    final apk = CertLabSnapshot(
      node: CertLabNodeId.android,
      at: DateTime.now().toUtc(),
      counts: const {'productos': 1, 'clientes': 0, 'proveedores': 0},
      stockByCodigo: const {'pruebq': 33},
      precioByCodigo: const {'pruebq': 10},
      saldoByCliente: const {},
      docIds: const {},
      stockOpIds: const {},
    );
    final cloud = CertLabSnapshot(
      node: CertLabNodeId.firestore,
      at: DateTime.now().toUtc(),
      counts: const {'productos': 1, 'clientes': 0, 'proveedores': 0},
      stockByCodigo: const {'pruebq': 33},
      precioByCodigo: const {'pruebq': 10},
      saldoByCliente: const {},
      docIds: const {},
      stockOpIds: const {},
    );
    final fail = CertLabOracle.compareTriple(
      scenarioId: 'campo-pruebq',
      windows: win,
      android: apk,
      firestore: cloud,
      events: events,
    );
    expect(fail, isNotNull);
    expect(fail!.entity, CertLabEntity.stock);
    expect(fail.where, 'stock[pruebq]');
    expect(fail.firstDivergentEvent?.seq, 1);
    expect(fail.sql, contains('pruebq'));
    expect(fail.file, isNotNull);
    expect(fail.clazz, 'CertLabOracle');
    expect(fail.method, 'compareTriple');
  });
}
