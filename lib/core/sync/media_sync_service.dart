import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import '../config/backend_config_service.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../utils/media_path.dart';

/// Sube fotos/archivos locales a Firebase Storage y devuelve URLs públicas.
class MediaSyncService {
  MediaSyncService._();
  static final MediaSyncService instance = MediaSyncService._();

  String? lastError;

  /// Bucket que ya funcionó en esta sesión (evita reintentar el incorrecto).
  String? _bucketOk;

  bool get _ok =>
      BackendConfigService.instance.firebaseEnabled &&
      FirebaseBootstrap.isReady &&
      FirebaseAuthUsuarioService.instance.uidActual != null;

  bool get nubeDisponible => _ok;

  String get tenantId => _tenant;

  String get _tenant => BackendConfigService.instance.tenantId;

  /// Candidatos: el de firebase_options + legacy appspot (mismatch frecuente).
  List<String> get _bucketCandidates {
    final configured =
        DefaultFirebaseOptions.currentPlatform.storageBucket ?? '';
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    final ordered = <String>[
      ?_bucketOk,
      if (configured.isNotEmpty) configured,
      if (projectId.isNotEmpty) '$projectId.firebasestorage.app',
      if (projectId.isNotEmpty) '$projectId.appspot.com',
    ];
    final seen = <String>{};
    return [
      for (final b in ordered)
        if (b.isNotEmpty && seen.add(b.replaceFirst('gs://', '')))
          b.replaceFirst('gs://', ''),
    ];
  }

  FirebaseStorage _storageFor(String bucket) {
    final name = bucket.startsWith('gs://') ? bucket : 'gs://$bucket';
    return FirebaseStorage.instanceFor(bucket: name);
  }

  String _mensajeError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'object-not-found':
          return 'Storage no encuentra el bucket/archivo '
              '(object-not-found). En Firebase Console → Storage: '
              'asegurate de que Storage esté creado y publicá las reglas '
              'de storage.rules (lectura/escritura con sesión). '
              'Después reiniciá la app e intentá de nuevo.';
        case 'unauthorized':
        case 'permission-denied':
          return 'Sin permiso en Storage. Publicá storage.rules '
              '(auth != null en tenants/) e iniciá sesión de nuevo.';
        case 'unauthenticated':
          return 'Sesión Firebase vencida. Cerrá sesión e ingresá de nuevo.';
        case 'retry-limit-exceeded':
        case 'canceled':
          return 'Subida interrumpida. Revisá internet e intentá otra vez.';
        default:
          return '[${e.plugin}/${e.code}] ${e.message ?? e}';
      }
    }
    return '$e';
  }

  Future<String> _downloadUrlConReintento(Reference ref) async {
    Object? last;
    for (var i = 0; i < 4; i++) {
      try {
        if (i > 0) {
          await Future<void>.delayed(Duration(milliseconds: 250 * i));
        }
        return await ref.getDownloadURL();
      } catch (e) {
        last = e;
        debugPrint('MediaSync getDownloadURL intento ${i + 1}: $e');
      }
    }
    throw last ?? StateError('getDownloadURL falló');
  }

  Future<String> _subirEnBucket({
    required String bucket,
    required String storagePath,
    required File file,
    required String contentType,
  }) async {
    final storage = _storageFor(bucket);
    final ref = storage.ref().child(storagePath);
    final meta = SettableMetadata(contentType: contentType);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('La foto está vacía.');
    }

    // putData + snapshot (más fiable que await suelto + getDownloadURL).
    try {
      final TaskSnapshot snap = await ref.putData(bytes, meta);
      if (snap.state != TaskState.success) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'unknown',
          message: 'Upload state=${snap.state}',
        );
      }
      final url = await _downloadUrlConReintento(snap.ref);
      debugPrint('MediaSync OK putData → gs://$bucket/$storagePath');
      return url;
    } catch (e) {
      debugPrint('MediaSync putData ($bucket) falló: $e');
    }

    // Fallback putFile (mismo bucket).
    final TaskSnapshot snap = await ref.putFile(file, meta);
    if (snap.state != TaskState.success) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unknown',
        message: 'Upload state=${snap.state}',
      );
    }
    final url = await _downloadUrlConReintento(snap.ref);
    debugPrint('MediaSync OK putFile → gs://$bucket/$storagePath');
    return url;
  }

  /// Copia una imagen temporal (ImagePicker) a almacenamiento permanente.
  Future<String?> persistirFotoLocal({
    required String sourcePath,
    required String codigoProducto,
  }) async {
    if (sourcePath.isEmpty || esUrlRemota(sourcePath)) return sourcePath;
    final source = File(sourcePath);
    if (!source.existsSync()) return null;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'productos_fotos'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safeCodigo =
          codigoProducto.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final ext =
          p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
      final dest = p.join(
        dir.path,
        '${safeCodigo}_${const Uuid().v4()}$ext',
      );
      final alreadyPersisted = p.normalize(p.dirname(sourcePath)) ==
          p.normalize(dir.path);
      if (alreadyPersisted) {
        return sourcePath;
      }
      await source.copy(dest);
      return dest;
    } catch (e) {
      debugPrint('MediaSync persistirFotoLocal: $e');
      return sourcePath;
    }
  }

  Future<String?> subirArchivo({
    required String storagePath,
    required File file,
    String contentType = 'application/octet-stream',
  }) async {
    lastError = null;
    if (!_ok) {
      lastError =
          'Nube no lista (Firebase/auth). Activá sync e iniciá sesión de nuevo.';
      return null;
    }
    if (!file.existsSync()) {
      lastError = 'No se encontró el archivo local de la foto.';
      return null;
    }

    Object? last;
    for (final bucket in _bucketCandidates) {
      try {
        final url = await _subirEnBucket(
          bucket: bucket,
          storagePath: storagePath,
          file: file,
          contentType: contentType,
        );
        _bucketOk = bucket;
        lastError = null;
        return url;
      } catch (e) {
        last = e;
        debugPrint('MediaSync bucket $bucket: $e');
      }
    }

    lastError = _mensajeError(last ?? 'error desconocido');
    return null;
  }

  /// 1) Persiste rutas temporales en disco de la app
  /// 2) Si hay nube, sube a Storage y devuelve HTTPS
  /// 3) Si no hay nube, deja la ruta permanente local
  Future<List<String>> sincronizarFotosProducto(
    String codigo,
    List<String> rutas,
  ) async {
    if (rutas.isEmpty) return const [];

    final persistidas = <String>[];
    for (final ruta in rutas) {
      if (ruta.isEmpty) continue;
      if (esUrlRemota(ruta)) {
        persistidas.add(ruta);
        continue;
      }
      final local = await persistirFotoLocal(
        sourcePath: ruta,
        codigoProducto: codigo,
      );
      if (local != null && local.isNotEmpty) {
        persistidas.add(local);
      }
    }
    if (persistidas.isEmpty) return const [];
    if (!_ok) return persistidas;

    final resultado = <String>[];
    var i = 0;
    for (final ruta in persistidas) {
      if (esUrlRemota(ruta)) {
        resultado.add(ruta);
        continue;
      }
      final file = File(ruta);
      if (!file.existsSync()) continue;
      final ext = p.extension(ruta).isNotEmpty ? p.extension(ruta) : '.jpg';
      final safeCodigo = codigo.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final url = await subirArchivo(
        storagePath:
            'tenants/$_tenant/productos/$safeCodigo/foto_${i}_${const Uuid().v4()}$ext',
        file: file,
        contentType: 'image/jpeg',
      );
      if (url != null) {
        resultado.add(url);
        i++;
      } else {
        // Queda local; el caller debe avisar si la nube está activa.
        resultado.add(ruta);
      }
    }
    return resultado;
  }

  /// Solo URLs https para escribir en Firestore (nunca paths de otro dispositivo).
  List<String> soloUrlsRemotas(List<String> rutas) =>
      rutas.where(esUrlRemota).toList();

  Future<String?> subirAdjuntoChat({
    required String conversacionId,
    required File file,
    String contentType = 'application/octet-stream',
  }) async {
    final nombre = p.basename(file.path);
    return subirArchivo(
      storagePath:
          'tenants/$_tenant/chats/$conversacionId/${const Uuid().v4()}_$nombre',
      file: file,
      contentType: contentType,
    );
  }

  Future<String?> subirFotoUsuario({
    required String uidOrUsuario,
    required File file,
  }) async {
    final safe = uidOrUsuario.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ext = p.extension(file.path).isNotEmpty ? p.extension(file.path) : '.jpg';
    return subirArchivo(
      storagePath:
          'tenants/$_tenant/usuarios/$safe/avatar_${const Uuid().v4()}$ext',
      file: file,
      contentType: 'image/jpeg',
    );
  }

  Future<String?> subirPdfCliente({
    required String clienteSyncId,
    required String nombreArchivo,
    required File file,
  }) async {
    final safeCliente =
        clienteSyncId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeNombre = nombreArchivo.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return subirArchivo(
      storagePath: 'tenants/$_tenant/pdfs/$safeCliente/$safeNombre',
      file: file,
      contentType: 'application/pdf',
    );
  }
}
