import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config_service.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../utils/media_path.dart';

/// Sube fotos/archivos locales a Firebase Storage y devuelve URLs públicas.
class MediaSyncService {
  MediaSyncService._();
  static final MediaSyncService instance = MediaSyncService._();

  String? lastError;

  bool get _ok =>
      BackendConfigService.instance.firebaseEnabled &&
      FirebaseBootstrap.isReady &&
      FirebaseAuthUsuarioService.instance.uidActual != null;

  bool get nubeDisponible => _ok;

  String get _tenant => BackendConfigService.instance.tenantId;

  FirebaseStorage get _storage => FirebaseStorage.instance;

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

    final ref = _storage.ref().child(storagePath);
    final meta = SettableMetadata(contentType: contentType);

    // 1) putData (más fiable en Android que putFile con rutas del picker)
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        lastError = 'La foto está vacía.';
        return null;
      }
      await ref.putData(bytes, meta);
      final url = await ref.getDownloadURL();
      debugPrint('MediaSync OK putData → $storagePath');
      return url;
    } catch (e) {
      debugPrint('MediaSync putData falló: $e');
      lastError = '$e';
    }

    // 2) Fallback putFile
    try {
      await ref.putFile(file, meta);
      final url = await ref.getDownloadURL();
      debugPrint('MediaSync OK putFile → $storagePath');
      lastError = null;
      return url;
    } catch (e) {
      debugPrint('MediaSync putFile falló: $e');
      lastError = '$e';
      return null;
    }
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
