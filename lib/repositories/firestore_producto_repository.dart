import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/config/backend_config_service.dart';
import '../core/config/platform_capabilities.dart';
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

  CollectionReference<Map<String, dynamic>> get _stockOpsCol {
    final tenant = BackendConfigService.instance.tenantId;
    return _firestore.collection('tenants').doc(tenant).collection('stock_ops');
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

  /// Catálogo paginado por id de documento (Windows: sin techo alfabético).
  Future<({List<Producto> items, String? lastDocId, bool done})>
      obtenerPaginaPorDocId({
    String? afterDocId,
    int limit = 120,
  }) async {
    Query<Map<String, dynamic>> q =
        _collection.orderBy(FieldPath.documentId).limit(limit);
    if (afterDocId != null && afterDocId.isNotEmpty) {
      q = q.startAfter([afterDocId]);
    }
    final snap = await q.get();
    final items = snap.docs
        .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
        .toList();
    final lastDocId = snap.docs.isEmpty ? afterDocId : snap.docs.last.id;
    return (
      items: items,
      lastDocId: lastDocId,
      done: snap.docs.length < limit,
    );
  }

  /// Cambios recientes de stock/metadata (orden por actualizadoEn).
  Future<({List<Producto> items, String? lastTs, bool done})>
      obtenerActualizadosDesde({
    String? afterTs,
    int limit = 100,
  }) async {
    Query<Map<String, dynamic>> q =
        _collection.orderBy('actualizadoEn').limit(limit);
    if (afterTs != null && afterTs.isNotEmpty) {
      q = q.startAfter([afterTs]);
    }
    final snap = await q.get();
    final items = snap.docs
        .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
        .toList();
    String? lastTs = afterTs;
    for (final p in items) {
      final ts = p.actualizadoEn?.trim();
      if (ts != null && ts.isNotEmpty) lastTs = ts;
    }
    return (
      items: items,
      lastTs: lastTs,
      done: snap.docs.length < limit,
    );
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

  /// Ajuste de stock en la nube (Capacidad 6).
  ///
  /// Idempotente por `stock_ops/{opId}` dentro de una **transacción**
  /// (claim + increment atómicos). Si la txn no está disponible (p. ej. rare
  /// Windows), cae a create-condicional + marca `pending_apply` para reintento.
  Future<void> ajustarStock({
    required String codigo,
    required int delta,
    required String opId,
  }) async {
    final cod = codigo.trim();
    if (cod.isEmpty || delta == 0 || opId.isEmpty) return;

    // Windows: runTransaction cuelga/tumba el .exe → camino sin txn.
    if (PlatformCapabilities.isWindowsDesktop) {
      await _ajustarStockWindowsSafe(cod: cod, delta: delta, opId: opId);
      return;
    }

    try {
      await _ajustarStockEnTransaccion(cod: cod, delta: delta, opId: opId);
    } catch (e) {
      // Solo fallback si la plataforma no soporta txn (no ante errores lógicos).
      final msg = e.toString().toLowerCase();
      final txnUnavailable = msg.contains('unavailable') ||
          msg.contains('unimplemented') ||
          msg.contains('not supported') ||
          msg.contains('no firebase app');
      if (!txnUnavailable) rethrow;
      debugPrint('stock_ops txn unavailable: $e — fallback create-only');
      await _ajustarStockConCreate(cod: cod, delta: delta, opId: opId);
    }
  }

  /// Windows: get + claim + increment con timeouts (sin runTransaction).
  /// Idempotente: si `stock_ops/{opId}` ya existe, no re-incrementa.
  Future<void> _ajustarStockWindowsSafe({
    required String cod,
    required int delta,
    required String opId,
  }) async {
    final opRef = _stockOpsCol.doc(opId);
    final prodRef = _collection.doc(cod);
    final ahora = DateTime.now().toUtc().toIso8601String();
    final claim = const Uuid().v4();

    final existing = await opRef.get().timeout(const Duration(seconds: 8));
    if (existing.exists) return;

    await opRef
        .set({
          'codigo': cod,
          'delta': delta,
          'status': 'applied',
          'at': ahora,
          'appliedAt': ahora,
          'via': 'windows_safe',
          'claim': claim,
        })
        .timeout(const Duration(seconds: 8));

    // Si perdimos la carrera, el claim no es nuestro → no incrementar.
    final check = await opRef.get().timeout(const Duration(seconds: 5));
    if ((check.data()?['claim']?.toString() ?? '') != claim) return;

    await prodRef
        .set({
          'codigo': cod,
          'stock': FieldValue.increment(delta),
          'actualizadoEn': ahora,
          'ultimaStockOp': opId,
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 8));
  }

  /// Idempotente estricto: si `stock_ops/{opId}` ya existe → no re-incrementa.
  Future<void> _ajustarStockEnTransaccion({
    required String cod,
    required int delta,
    required String opId,
  }) async {
    final opRef = _stockOpsCol.doc(opId);
    final prodRef = _collection.doc(cod);
    final ahora = DateTime.now().toUtc().toIso8601String();

    await _firestore.runTransaction((txn) async {
      final opSnap = await txn.get(opRef);
      if (opSnap.exists) {
        // Ya aplicada o claimed por otro: NUNCA incrementar de nuevo.
        return;
      }
      txn.set(opRef, {
        'codigo': cod,
        'delta': delta,
        'status': 'applied',
        'at': ahora,
        'appliedAt': ahora,
      });
      final prodSnap = await txn.get(prodRef);
      final ultima = prodSnap.data()?['ultimaStockOp']?.toString();
      if (ultima == opId) {
        // Producto ya refleja esta op (retry raro) — solo asegurar op applied.
        return;
      }
      txn.set(
        prodRef,
        {
          'codigo': cod,
          'stock': FieldValue.increment(delta),
          'actualizadoEn': ahora,
          'ultimaStockOp': opId,
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Fallback sin txn: solo marca pending; el próximo flush reintenta txn.
  /// Nunca incrementa stock fuera de transacción (evita doble delta).
  Future<void> _ajustarStockConCreate({
    required String cod,
    required int delta,
    required String opId,
  }) async {
    final opRef = _stockOpsCol.doc(opId);
    final existing = await opRef.get();
    if (existing.exists) return;
    final ahora = DateTime.now().toUtc().toIso8601String();
    await opRef.set({
      'codigo': cod,
      'delta': delta,
      'status': 'pending_apply',
      'at': ahora,
      'error': 'txn_unavailable',
    }, SetOptions(merge: true));
    throw StateError(
      'stock_ops: txn no disponible; op $opId quedó pending_apply',
    );
  }

  /// Página de stock_ops por tiempo (`at`) — no por docId (UUID random
  /// hacía perder ops nuevas respecto del watermark).
  Future<
      ({
        List<Map<String, dynamic>> items,
        String? lastAt,
        String? lastDocId,
        bool done,
      })> obtenerStockOpsPagina({
    String? afterDocId,
    String? afterAt,
    int limit = 80,
  }) async {
    // Un solo orderBy('at'): índice automático, sin composite.
    Query<Map<String, dynamic>> q = _stockOpsCol.orderBy('at').limit(limit);
    final at = (afterAt ?? '').trim();
    if (at.isNotEmpty) {
      q = q.startAfter([at]);
    }
    final snap = await q.get();
    final items = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['opId'] = doc.id;
      items.add(data);
    }
    String? lastAtOut = afterAt;
    String? lastDocOut = afterDocId;
    if (snap.docs.isNotEmpty) {
      lastDocOut = snap.docs.last.id;
      lastAtOut = snap.docs.last.data()['at']?.toString() ?? lastAtOut;
    }
    return (
      items: items,
      lastAt: lastAtOut,
      lastDocId: lastDocOut,
      done: snap.docs.length < limit,
    );
  }

  /// Últimas stock_ops (APK/desktop) para convergencia casi en vivo.
  Future<List<Map<String, dynamic>>> obtenerStockOpsRecientes({
    int limit = 40,
  }) async {
    final snap =
        await _stockOpsCol.orderBy('at', descending: true).limit(limit).get();
    return snap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['opId'] = doc.id;
      return data;
    }).toList();
  }

  /// Completa ops pending/claimed solo si el producto aún no refleja la op.
  Future<int> reconcilizarStockOpsPendientes({int limit = 50}) async {
    var ok = 0;
    for (final status in const ['pending_apply', 'claimed']) {
      final snap = await _stockOpsCol
          .where('status', isEqualTo: status)
          .limit(limit)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final cod = data['codigo']?.toString().trim() ?? '';
        final delta = (data['delta'] as num?)?.toInt() ?? 0;
        if (cod.isEmpty || delta == 0) continue;
        try {
          final prod = await _collection.doc(cod).get();
          final ultima = prod.data()?['ultimaStockOp']?.toString();
          if (ultima == doc.id) {
            await doc.reference.set({
              'status': 'applied',
              'appliedAt': DateTime.now().toUtc().toIso8601String(),
            }, SetOptions(merge: true));
            ok++;
            continue;
          }
          // Borrar claim incompleto y reaplicar vía txn idempotente.
          // Si otro device ya aplicó, txn verá op inexistente o…
          // Mantener el doc: txn actual exige !exists. Si pending existe,
          // hay que borrarlo o actualizar status en la txn.
          await _firestore.runTransaction((txn) async {
            final opRef = doc.reference;
            final opSnap = await txn.get(opRef);
            if (!opSnap.exists) return;
            final st = opSnap.data()?['status']?.toString() ?? '';
            if (st == 'applied') return;
            final prodRef = _collection.doc(cod);
            final prodSnap = await txn.get(prodRef);
            if (prodSnap.data()?['ultimaStockOp']?.toString() == doc.id) {
              txn.set(opRef, {
                'status': 'applied',
                'appliedAt': DateTime.now().toUtc().toIso8601String(),
              }, SetOptions(merge: true));
              return;
            }
            final ahora = DateTime.now().toUtc().toIso8601String();
            txn.set(
              prodRef,
              {
                'codigo': cod,
                'stock': FieldValue.increment(delta),
                'actualizadoEn': ahora,
                'ultimaStockOp': doc.id,
              },
              SetOptions(merge: true),
            );
            txn.set(opRef, {
              'codigo': cod,
              'delta': delta,
              'status': 'applied',
              'at': ahora,
              'appliedAt': ahora,
            }, SetOptions(merge: true));
          });
          ok++;
        } catch (e) {
          debugPrint('reconcilizar stock_ops ${doc.id}: $e');
        }
      }
    }
    return ok;
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
    return watchSnapshots(limit: limit).map(
      (snap) => snap.docs
          .map((doc) => Producto.fromFirestore(doc.data(), docId: doc.id))
          .toList(),
    );
  }

  /// Snapshot crudo para aplicar solo [DocumentChange]s en sync.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchSnapshots({
    int limit = 10000,
  }) {
    return _collection.limit(limit).snapshots();
  }
}
