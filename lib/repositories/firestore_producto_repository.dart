import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/backend_config_service.dart';
import '../models/producto.dart';
import 'producto_repository.dart';

class FirestoreProductoRepository implements ProductoRepository {
  FirestoreProductoRepository({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Lazy: no tocar Firebase al construir el repo (login local en Windows).
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection {
    final tenant = BackendConfigService.instance.tenantId;
    return _firestore.collection('tenants').doc(tenant).collection('productos');
  }

  String _docId(Producto producto) =>
      producto.codigo.trim().isEmpty ? producto.id.toString() : producto.codigo.trim();

  @override
  Future<int> insertar(Producto producto) async {
    final docId = _docId(producto);
    await _collection.doc(docId).set(producto.toFirestore(), SetOptions(merge: true));
    return producto.id ?? docId.hashCode;
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    // Firestore admite máx. 500 ops por batch.
    const chunk = 400;
    for (var i = 0; i < productos.length; i += chunk) {
      final slice = productos.skip(i).take(chunk);
      final batch = _firestore.batch();
      for (final producto in slice) {
        final ref = _collection.doc(_docId(producto));
        batch.set(ref, producto.toFirestore(), SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  @override
  Future<List<Producto>> obtenerTodos({int? limit, int? offset}) async {
    Query<Map<String, dynamic>> query =
        _collection.orderBy('descripcion').limit(limit ?? 10000);
    if (offset != null && offset > 0) {
      // Firestore no usa offset clásico; para miles de productos se pagina por cursor.
      final skipSnap = await _collection.orderBy('descripcion').limit(offset).get();
      if (skipSnap.docs.isEmpty) return [];
      query = _collection
          .orderBy('descripcion')
          .startAfterDocument(skipSnap.docs.last)
          .limit(limit ?? 10000);
    }
    final snap = await query.get();
    return snap.docs
        .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
        .toList();
  }

  @override
  Future<Producto?> buscarPorCodigo(String codigo) async {
    final direct = await _collection.doc(codigo).get();
    if (direct.exists) {
      return Producto.fromFirestore(direct.data()!, docId: direct.id);
    }
    final snap = await _collection.where('codigo', isEqualTo: codigo).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return Producto.fromFirestore(doc.data(), docId: doc.id);
  }

  @override
  Future<Producto?> buscarPorCodigoBarras(String codigoBarras) async {
    if (codigoBarras.trim().isEmpty) return null;
    final snap = await _collection
        .where('codigo_barras', isEqualTo: codigoBarras)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      return Producto.fromFirestore(doc.data(), docId: doc.id);
    }
    return buscarPorCodigo(codigoBarras);
  }

  @override
  Future<bool> tieneProductos() async {
    final snap = await _collection.limit(1).get();
    return snap.docs.isNotEmpty;
  }

  @override
  Future<int> actualizar(Producto producto) async {
    await _collection.doc(_docId(producto)).set(
          producto.toFirestore(),
          SetOptions(merge: true),
        );
    return 1;
  }

  /// Sube metadata sin pisar stock absoluto (los deltas van por [ajustarStock]).
  Future<void> actualizarSinStock(Producto producto) async {
    final data = producto.toFirestore()..remove('stock');
    await _collection.doc(_docId(producto)).set(data, SetOptions(merge: true));
  }

  /// Ajuste atómico e idempotente de stock en la nube (Fase 2).
  Future<void> ajustarStock({
    required String codigo,
    required int delta,
    required String opId,
  }) async {
    final cod = codigo.trim();
    if (cod.isEmpty || delta == 0 || opId.isEmpty) return;
    final ref = _collection.doc(cod);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final ops = Map<String, dynamic>.from(
        (data['stockOps'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
            {},
      );
      if (ops.containsKey(opId)) return;
      ops[opId] = delta;
      // Evitar crecimiento infinito del mapa.
      if (ops.length > 300) {
        final keys = ops.keys.toList()..sort();
        for (final k in keys.take(ops.length - 250)) {
          ops.remove(k);
        }
      }
      final stockActual = (data['stock'] as num?)?.toInt() ?? 0;
      tx.set(
        ref,
        {
          'stock': stockActual + delta,
          'stockOps': ops,
          'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
          if (!snap.exists) 'codigo': cod,
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Future<int> eliminar(int id) async {
    return 0;
  }

  Future<void> eliminarPorCodigo(String codigo) async {
    if (codigo.trim().isEmpty) return;
    await _collection.doc(codigo.trim()).delete();
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 10000}) {
    // Fase 2: incluir soft-deleted para propagar papelera entre dispositivos.
    return _collection.limit(limit).snapshots().map(
          (snap) => snap.docs
              .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
              .toList(),
        );
  }
}
