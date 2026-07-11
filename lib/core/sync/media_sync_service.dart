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

  /// Copia una foto de producto a almacenamiento permanente de la app.
  /// Evita que Android borre el cache del image_picker antes de subir.
  Future<String> persistirFotoProducto({
    required String sourcePath,
    required String codigo,
  }) async {
    if (sourcePath.isEmpty || esUrlRemota(sourcePath)) return sourcePath;
    final source = File(sourcePath);
    if (!source.existsSync()) return sourcePath;

    final dir = await getApplicationDocumentsDirectory();
    final fotosDir = Directory(p.join(dir.path, 'productos_fotos'));
    if (!await fotosDir.exists()) {
      await fotosDir.create(recursive: true);
    }
    // Si ya está en nuestra carpeta, reutilizar.
    if (p.isWithin(fotosDir.path, sourcePath)) return sourcePath;

    final ext =
        p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
    final safe = codigo.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final dest = p.join(
      fotosDir.path,
      '${safe.isEmpty ? 'prod' : safe}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await source.copy(dest);
    return dest;
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
