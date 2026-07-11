import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/backend_config_service.dart';
import '../models/producto.dart';
import 'producto_repository.dart';

class FirestoreProductoRepository implements ProductoRepository {
  FirestoreProductoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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
    final batch = _firestore.batch();
    for (final producto in productos) {
      final ref = _collection.doc(_docId(producto));
      batch.set(ref, producto.toFirestore(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  @override
  Future<List<Producto>> obtenerTodos({int? limit, int? offset}) async {
    Query<Map<String, dynamic>> query =
        _collection.orderBy('descripcion').limit(limit ?? 500);
    if (offset != null && offset > 0) {
      // Firestore no usa offset clásico; para miles de productos se pagina por cursor.
      final skipSnap = await _collection.orderBy('descripcion').limit(offset).get();
      if (skipSnap.docs.isEmpty) return [];
      query = _collection
          .orderBy('descripcion')
          .startAfterDocument(skipSnap.docs.last)
          .limit(limit ?? 500);
    }
    final snap = await query.get();
    return snap.docs
        .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
        .where((p) => !p.estaEliminado)
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

  @override
  Future<int> eliminar(int id) async {
    return 0;
  }

  Future<void> eliminarPorCodigo(String codigo) async {
    if (codigo.trim().isEmpty) return;
    await _collection.doc(codigo.trim()).delete();
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 200}) {
    // limit <= 0 => sin tope (catálogo completo para sync multi-dispositivo).
    final query = limit <= 0
        ? _collection.orderBy('descripcion')
        : _collection.orderBy('descripcion').limit(limit);
    return query.snapshots().map(
          (snap) => snap.docs
              .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
              .toList(),
        );
  }
}
