import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/config/backend_config_service.dart';
import '../core/config/platform_capabilities.dart';
import '../core/sync/stock_ops_windows_policy.dart';
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
    String? documentType,
    String? documentId,
  }) async {
    final cod = codigo.trim();
    if (cod.isEmpty || delta == 0 || opId.isEmpty) return;

    // Windows: runTransaction cuelga/tumba el .exe → camino sin txn.
    if (PlatformCapabilities.isWindowsDesktop) {
      await _ajustarStockWindowsSafe(
        cod: cod,
        delta: delta,
        opId: opId,
        documentType: documentType,
        documentId: documentId,
      );
      return;
    }

    try {
      await _ajustarStockEnTransaccion(
        cod: cod,
        delta: delta,
        opId: opId,
        documentType: documentType,
        documentId: documentId,
      );
    } catch (e) {
      // Solo fallback si la plataforma no soporta txn (no ante errores lógicos).
      final msg = e.toString().toLowerCase();
      final txnUnavailable = msg.contains('unavailable') ||
          msg.contains('unimplemented') ||
          msg.contains('not supported') ||
          msg.contains('no firebase app');
      if (!txnUnavailable) rethrow;
      debugPrint('stock_ops txn unavailable: $e — fallback create-only');
      await _ajustarStockConCreate(
        cod: cod,
        delta: delta,
        opId: opId,
        documentType: documentType,
        documentId: documentId,
      );
    }
  }

  Map<String, dynamic> _stockOpMeta({
    required String cod,
    required int delta,
    required String opId,
    required String ahora,
    String? documentType,
    String? documentId,
  }) {
    final meta = <String, dynamic>{
      'codigo': cod,
      'delta': delta,
      'at': ahora,
      'opId': opId,
    };
    final dt = (documentType ?? '').trim();
    final di = (documentId ?? '').trim();
    if (dt.isNotEmpty) meta['documentType'] = dt;
    if (di.isNotEmpty) meta['documentId'] = di;
    return meta;
  }

  /// Windows: pending_apply → increment → applied (nunca applied sin increment).
  Future<void> _ajustarStockWindowsSafe({
    required String cod,
    required int delta,
    required String opId,
    String? documentType,
    String? documentId,
  }) async {
    final opRef = _stockOpsCol.doc(opId);
    final prodRef = _collection.doc(cod);
    final ahora = DateTime.now().toUtc().toIso8601String();
    final claim = const Uuid().v4();
    final base = _stockOpMeta(
      cod: cod,
      delta: delta,
      opId: opId,
      ahora: ahora,
      documentType: documentType,
      documentId: documentId,
    );

    final existing = await opRef.get().timeout(const Duration(seconds: 8));
    final prodSnap = await prodRef.get().timeout(const Duration(seconds: 8));
    final ultima = prodSnap.data()?['ultimaStockOp']?.toString();
    final phase = classifyStockOpCloud(
      exists: existing.exists,
      status: existing.data()?['status']?.toString(),
      ultimaStockOpProducto: ultima,
      opId: opId,
    );

    if (phase == StockOpCloudPhase.appliedComplete) return;

    if (phase == StockOpCloudPhase.missing) {
      await opRef
          .set({
            ...base,
            'status': 'pending_apply',
            'via': 'windows_safe',
            'claim': claim,
          })
          .timeout(const Duration(seconds: 8));
      final check = await opRef.get().timeout(const Duration(seconds: 5));
      if ((check.data()?['claim']?.toString() ?? '') != claim) {
        // Perdimos la carrera: NO ACK hasta prueba de applied.
        final st = check.data()?['status']?.toString();
        if (st == 'applied') return;
        throw StateError(
          'stock_ops: lost claim on $opId (status=$st); keep outbox pending',
        );
      }
    }

    // Completar increment solo si la op aún no está applied (pending).
    if (stockOpNeedsIncrement(phase) || phase == StockOpCloudPhase.missing) {
      // Guard: re-leer status (otro writer pudo completar).
      final again = await opRef.get().timeout(const Duration(seconds: 5));
      if (again.data()?['status']?.toString() == 'applied') return;

      await prodRef
          .set({
            'codigo': cod,
            'stock': FieldValue.increment(delta),
            'actualizadoEn': ahora,
            'ultimaStockOp': opId,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    }

    await opRef
        .set({
          ...base,
          'status': 'applied',
          'appliedAt': ahora,
          'incrementApplied': true,
          'via': 'windows_safe',
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 8));
  }

  /// Idempotente estricto: si `stock_ops/{opId}` ya applied completo → no-op.
  Future<void> _ajustarStockEnTransaccion({
    required String cod,
    required int delta,
    required String opId,
    String? documentType,
    String? documentId,
  }) async {
    final opRef = _stockOpsCol.doc(opId);
    final prodRef = _collection.doc(cod);
    final ahora = DateTime.now().toUtc().toIso8601String();
    final base = _stockOpMeta(
      cod: cod,
      delta: delta,
      opId: opId,
      ahora: ahora,
      documentType: documentType,
      documentId: documentId,
    );

    await _firestore.runTransaction((txn) async {
      final opSnap = await txn.get(opRef);
      final phase = classifyStockOpCloud(
        exists: opSnap.exists,
        status: opSnap.data()?['status']?.toString(),
        opId: opId,
      );
      if (phase == StockOpCloudPhase.appliedComplete) return;

      if (phase == StockOpCloudPhase.missing) {
        txn.set(opRef, {
          ...base,
          'status': 'pending_apply',
        });
      }

      if (stockOpNeedsIncrement(phase) ||
          phase == StockOpCloudPhase.missing) {
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
      }
      txn.set(opRef, {
        ...base,
        'status': 'applied',
        'appliedAt': ahora,
        'incrementApplied': true,
      }, SetOptions(merge: true));
    });
  }

  /// Fallback sin txn: solo marca pending; NUNCA retorna éxito sin applied.
  Future<void> _ajustarStockConCreate({
    required String cod,
    required int delta,
    required String opId,
    String? documentType,
    String? documentId,
  }) async {
    final opRef = _stockOpsCol.doc(opId);
    final existing = await opRef.get();
    if (existing.exists) {
      final st = existing.data()?['status']?.toString();
      if (st == 'applied') return;
      throw StateError(
        'stock_ops: $opId existe como $st; falta applied (no ACK)',
      );
    }
    final ahora = DateTime.now().toUtc().toIso8601String();
    await opRef.set({
      ..._stockOpMeta(
        cod: cod,
        delta: delta,
        opId: opId,
        ahora: ahora,
        documentType: documentType,
        documentId: documentId,
      ),
      'status': 'pending_apply',
      'error': 'txn_unavailable',
    }, SetOptions(merge: true));
    throw StateError(
      'stock_ops: txn no disponible; op $opId quedó pending_apply',
    );
  }

  /// Página de stock_ops por (`at`, docId) — tie-break evita saltar ops
  /// con el mismo timestamp (C5).
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
    Query<Map<String, dynamic>> q = _stockOpsCol
        .orderBy('at')
        .orderBy(FieldPath.documentId)
        .limit(limit);
    final at = (afterAt ?? '').trim();
    final docId = (afterDocId ?? '').trim();
    if (at.isNotEmpty) {
      q = q.startAfter([at, docId]);
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

  /// Prueba C6: ¿la op quedó `applied` en nube? (por opId, no por ultimaStockOp).
  Future<bool> stockOpCloudApplied(String opId) async {
    if (opId.trim().isEmpty) return false;
    final opSnap = await _stockOpsCol.doc(opId).get();
    if (!opSnap.exists) return false;
    final data = opSnap.data() ?? const <String, dynamic>{};
    final phase = classifyStockOpCloud(
      exists: true,
      status: data['status']?.toString(),
      opId: opId,
    );
    return phase == StockOpCloudPhase.appliedComplete;
  }

  /// Completa ops pending/claimed. NUNCA re-procesa status=applied
  /// (evita doble increment cuando ultimaStockOp ya apunta a otra op).
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
          final phase = classifyStockOpCloud(
            exists: true,
            status: data['status']?.toString(),
            opId: doc.id,
          );
          if (phase == StockOpCloudPhase.appliedComplete) continue;
          await ajustarStock(
            codigo: cod,
            delta: delta,
            opId: doc.id,
            documentType: data['documentType']?.toString(),
            documentId: data['documentId']?.toString(),
          );
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
