import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../config/backend_config_service.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../utils/media_path.dart';

/// Sube fotos/archivos locales a Firebase Storage y devuelve URLs públicas.
class MediaSyncService {
  MediaSyncService._();
  static final MediaSyncService instance = MediaSyncService._();

  bool get _ok =>
      BackendConfigService.instance.firebaseEnabled &&
      FirebaseBootstrap.isReady &&
      FirebaseAuthUsuarioService.instance.uidActual != null;

  String get _tenant => BackendConfigService.instance.tenantId;

  Future<String?> subirArchivo({
    required String storagePath,
    required File file,
    String contentType = 'application/octet-stream',
  }) async {
    if (!_ok || !file.existsSync()) return null;
    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('MediaSync subirArchivo: $e');
      return null;
    }
  }

  /// Convierte rutas locales a URLs de Storage; deja intactas las URLs remotas.
  Future<List<String>> sincronizarFotosProducto(
    String codigo,
    List<String> rutas,
  ) async {
    if (rutas.isEmpty) return const [];
    if (!_ok) return rutas;

    final resultado = <String>[];
    var i = 0;
    for (final ruta in rutas) {
      if (ruta.isEmpty) continue;
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
        resultado.add(ruta); // fallback local
      }
    }
    return resultado;
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
