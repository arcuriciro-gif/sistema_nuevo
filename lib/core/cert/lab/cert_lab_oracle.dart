import 'cert_lab_models.dart';

/// Oráculo: Windows ≡ Android ≡ Firestore (proyección).
class CertLabOracle {
  /// Compara tres snapshots. Retorna null si OK, o el primer fallo.
  static CertLabFailure? compareTriple({
    required String scenarioId,
    required CertLabSnapshot windows,
    required CertLabSnapshot android,
    required CertLabSnapshot firestore,
    required List<CertLabEvent> events,
    Set<String> ignoreCountKeys = const {'outbox_pending', 'outbox_inflight'},
  }) {
    // 1) Stock por código
    final codes = <String>{
      ...windows.stockByCodigo.keys,
      ...android.stockByCodigo.keys,
      ...firestore.stockByCodigo.keys,
    }..removeWhere((c) => c.startsWith('__pad_'));

    for (final codigo in codes) {
      final w = windows.stockByCodigo[codigo] ?? 0;
      final a = android.stockByCodigo[codigo] ?? 0;
      final f = firestore.stockByCodigo[codigo] ?? 0;
      if (w != a || w != f) {
        return CertLabFailure(
          scenarioId: scenarioId,
          entity: CertLabEntity.stock,
          where: 'stock[$codigo]',
          message: 'Stock diverge entre nodos',
          expected: 'Win=Android=Firestore',
          actual: 'Win=$w Android=$a Firestore=$f',
          firstDivergentEvent: _lastStockEvent(events, codigo),
          file: 'lib/core/cert/lab/cert_lab_oracle.dart',
          clazz: 'CertLabOracle',
          method: 'compareTriple',
          firestorePath: 'tenants/{tenant}/stock_ops/* (proyección Σδ)',
          sql:
              "SELECT codigo, stock FROM productos WHERE codigo = '$codigo'",
          hint:
              'Autoridad = mismo conjunto de stock_ops applied. '
              'Si Win≠Android, faltó push/pull de un opId.',
        );
      }
    }

    // 2) Precios
    final priceCodes = <String>{
      ...windows.precioByCodigo.keys,
      ...android.precioByCodigo.keys,
      ...firestore.precioByCodigo.keys,
    }..removeWhere((c) => c.startsWith('__pad_'));
    for (final codigo in priceCodes) {
      final w = windows.precioByCodigo[codigo];
      final a = android.precioByCodigo[codigo];
      final f = firestore.precioByCodigo[codigo];
      if (w == null || a == null) continue;
      if (w != a || (f != null && f != w)) {
        return CertLabFailure(
          scenarioId: scenarioId,
          entity: CertLabEntity.precio,
          where: 'precio[$codigo]',
          message: 'Precio diverge',
          expected: w,
          actual: 'Win=$w Android=$a Firestore=$f',
          firstDivergentEvent: _lastEvent(events, CertLabEntity.precio, codigo),
          file: 'lib/core/cert/lab/cert_lab_oracle.dart',
          clazz: 'CertLabOracle',
          method: 'compareTriple',
          firestorePath: 'tenants/{tenant}/productos/$codigo',
          sql: "SELECT precio FROM productos WHERE codigo = '$codigo'",
        );
      }
    }

    // 3) Conteos de entidades
    for (final key in ['productos', 'clientes', 'proveedores']) {
      final w = windows.counts[key] ?? 0;
      final a = android.counts[key] ?? 0;
      final f = firestore.counts[key] ?? 0;
      if (ignoreCountKeys.contains(key)) continue;
      if (w != a || w != f) {
        final entity = switch (key) {
          'clientes' => CertLabEntity.cliente,
          'proveedores' => CertLabEntity.proveedor,
          _ => CertLabEntity.producto,
        };
        return CertLabFailure(
          scenarioId: scenarioId,
          entity: entity,
          where: 'count[$key]',
          message: 'Conteo diverge',
          expected: 'Win=Android=Firestore',
          actual: 'Win=$w Android=$a Firestore=$f',
          file: 'lib/core/cert/lab/cert_lab_oracle.dart',
          clazz: 'CertLabOracle',
          method: 'compareTriple',
          sql: 'SELECT COUNT(*) FROM $key',
          firestorePath: 'tenants/{tenant}/$key',
        );
      }
    }

    // 4) Saldos clientes (por nombre en lab)
    final clientes = <String>{
      ...windows.saldoByCliente.keys,
      ...android.saldoByCliente.keys,
    };
    for (final c in clientes) {
      final w = windows.saldoByCliente[c] ?? 0;
      final a = android.saldoByCliente[c] ?? 0;
      if (w != a) {
        return CertLabFailure(
          scenarioId: scenarioId,
          entity: CertLabEntity.cuentaCorriente,
          where: 'saldo[$c]',
          message: 'Saldo cliente diverge Win↔Android',
          expected: w,
          actual: a,
          sql: "SELECT saldo FROM clientes WHERE nombre = '$c'",
        );
      }
    }

    return null;
  }

  static CertLabEvent? _lastStockEvent(List<CertLabEvent> events, String codigo) {
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e.entity == CertLabEntity.stock &&
          e.payload['codigo']?.toString() == codigo) {
        return e;
      }
    }
    return events.isEmpty ? null : events.last;
  }

  static CertLabEvent? _lastEvent(
    List<CertLabEvent> events,
    CertLabEntity entity,
    String key,
  ) {
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e.entity == entity &&
          (e.payload['codigo']?.toString() == key ||
              e.payload['syncId']?.toString() == key ||
              e.payload['nombre']?.toString() == key)) {
        return e;
      }
    }
    return null;
  }
}
