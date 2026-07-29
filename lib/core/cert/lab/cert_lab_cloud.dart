import 'cert_lab_models.dart';

/// Firestore en memoria del laboratorio (no es el SDK real).
///
/// Representa el tercer nodo del oráculo: documentos + stock_ops applied.
class CertLabCloud {
  final Map<String, Map<String, Map<String, dynamic>>> _cols = {};
  final Map<String, Map<String, dynamic>> stockOps = {};
  final List<String> log = [];

  Map<String, Map<String, dynamic>> col(String name) =>
      _cols.putIfAbsent(name, () => <String, Map<String, dynamic>>{});

  void upsert(String collection, String id, Map<String, dynamic> data) {
    col(collection)[id] = Map<String, dynamic>.from(data)..['id'] = id;
    log.add('upsert:$collection/$id');
  }

  void delete(String collection, String id) {
    col(collection).remove(id);
    log.add('delete:$collection/$id');
  }

  Map<String, dynamic>? get(String collection, String id) {
    final d = col(collection)[id];
    return d == null ? null : Map<String, dynamic>.from(d);
  }

  /// stock_ops: autoridad de deltas entre nodos.
  void putStockOp({
    required String opId,
    required String codigo,
    required int delta,
    String status = 'applied',
    String? documentType,
    String? documentId,
    String? origin,
  }) {
    stockOps[opId] = {
      'opId': opId,
      'codigo': codigo,
      'delta': delta,
      'status': status,
      if (documentType != null) 'documentType': documentType,
      if (documentId != null) 'documentId': documentId,
      if (origin != null) 'origin': origin,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    };
    log.add('stock_op:$opId:$status');
  }

  bool hasStockOp(String opId) => stockOps.containsKey(opId);

  /// Proyección de stock en nube = Σ deltas applied (no absolutos).
  Map<String, int> projectedStock({Map<String, int> seed = const {}}) {
    final out = Map<String, int>.from(seed);
    for (final op in stockOps.values) {
      if (op['status']?.toString() != 'applied') continue;
      final codigo = op['codigo']?.toString() ?? '';
      if (codigo.isEmpty) continue;
      final delta = (op['delta'] as num?)?.toInt() ?? 0;
      out[codigo] = (out[codigo] ?? 0) + delta;
    }
    return out;
  }

  CertLabSnapshot snapshot({
    required Map<String, int> seedStock,
    Map<String, double> seedPrecios = const {},
  }) {
    final products = col('productos');
    final stock = projectedStock(seed: seedStock);
    final precios = <String, double>{...seedPrecios};
    for (final e in products.entries) {
      final codigo = e.value['codigo']?.toString() ?? e.key;
      final p = e.value['precio'];
      if (p is num) precios[codigo] = p.toDouble();
    }
    final clientes = col('clientes');
    final saldos = <String, double>{};
    for (final e in clientes.entries) {
      final key = e.value['syncId']?.toString() ?? e.key;
      saldos[key] = (e.value['saldo'] as num?)?.toDouble() ?? 0;
    }
    return CertLabSnapshot(
      node: CertLabNodeId.firestore,
      at: DateTime.now().toUtc(),
      counts: {
        'productos': products.length,
        'clientes': clientes.length,
        'proveedores': col('proveedores').length,
        'ventas': col('ventas').length,
        'compras': col('compras').length,
        'remitos': col('remitos').length,
        'stock_ops_applied':
            stockOps.values.where((o) => o['status'] == 'applied').length,
      },
      stockByCodigo: stock,
      precioByCodigo: precios,
      saldoByCliente: saldos,
      docIds: {
        'productos': products.keys.toSet(),
        'clientes': clientes.keys.toSet(),
        'proveedores': col('proveedores').keys.toSet(),
        'ventas': col('ventas').keys.toSet(),
        'compras': col('compras').keys.toSet(),
        'remitos': col('remitos').keys.toSet(),
      },
      stockOpIds: stockOps.keys.toSet(),
    );
  }

  void clear() {
    _cols.clear();
    stockOps.clear();
    log.clear();
  }
}
