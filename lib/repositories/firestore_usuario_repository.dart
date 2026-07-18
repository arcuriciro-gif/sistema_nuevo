import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/backend_config_service.dart';
import '../models/usuario.dart';
import 'usuario_repository.dart';

class FirestoreUsuarioRepository implements UsuarioRepository {
  FirestoreUsuarioRepository({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Lazy: no tocar Firebase al construir el repo (login local en Windows).
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection {
    final tenant = BackendConfigService.instance.tenantId;
    return _firestore.collection('tenants').doc(tenant).collection('usuarios');
  }

  @override
  Future<List<Usuario>> obtenerTodos() async {
    final snap = await _collection.orderBy('nombre').get();
    return snap.docs
        .map((doc) => Usuario.fromFirestore(doc.data(), docId: doc.id))
        .toList();
  }

  @override
  Future<Usuario?> buscarPorUsuario(String usuario) async {
    final snap = await _collection
        .where('usuario', isEqualTo: usuario.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return Usuario.fromFirestore(doc.data(), docId: doc.id);
  }

  @override
  Future<Usuario?> buscarPorFirebaseUid(String uid) async {
    final doc = await _collection.doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromFirestore(doc.data()!, docId: doc.id);
  }

  Future<Usuario?> buscarPorEmail(String email) async {
    final needle = email.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final snap =
        await _collection.where('email', isEqualTo: needle).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      return Usuario.fromFirestore(doc.data(), docId: doc.id);
    }
    // Fallback por si el email se guardó con mayúsculas.
    final todos = await obtenerTodos();
    try {
      return todos.firstWhere((u) => u.email.trim().toLowerCase() == needle);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> insertar(Usuario usuario) async {
    final uid = usuario.firebaseUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('firebaseUid requerido para guardar en Firestore.');
    }
    await _collection.doc(uid).set(usuario.toFirestore(), SetOptions(merge: true));
    return uid.hashCode;
  }

  @override
  Future<int> actualizar(Usuario usuario) async {
    final uid = usuario.firebaseUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('firebaseUid requerido para actualizar en Firestore.');
    }
    final data = usuario.toFirestore();
    // No pisar foto remota con path local vacío o de este dispositivo.
    final foto = data['foto']?.toString() ?? '';
    final esHttp = foto.startsWith('http://') || foto.startsWith('https://');
    if (!esHttp) {
      data.remove('foto');
    }
    await _collection.doc(uid).set(data, SetOptions(merge: true));
    return 1;
  }

  @override
  Future<int> desactivar(int id) async {
    return 0;
  }

  Future<void> desactivarPorUid(String uid) async {
    await _collection.doc(uid).set(
      {'activo': false, 'actualizadoEn': DateTime.now().toUtc().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  @override
  Future<bool> existeUsuario(String usuario) async {
    final encontrado = await buscarPorUsuario(usuario);
    return encontrado != null;
  }

  @override
  Stream<List<Usuario>> watchTodos() {
    return _collection.orderBy('nombre').snapshots().map(
          (snap) => snap.docs
              .map((doc) => Usuario.fromFirestore(doc.data(), docId: doc.id))
              .toList(),
        );
  }
}
