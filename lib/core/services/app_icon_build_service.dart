import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Prepara el icono elegido en Config para el próximo build nativo.
/// Copia a assets/branding y, si el proyecto fuente está disponible,
/// regenera mipmaps Android e icono Windows.
class AppIconBuildService {
  AppIconBuildService._();
  static final AppIconBuildService instance = AppIconBuildService._();

  Future<String> prepararDesdeArchivo(String iconoPath) async {
    if (iconoPath.isEmpty || !File(iconoPath).existsSync()) {
      throw StateError('No hay icono para preparar');
    }

    // Copia durable en documentos de la app
    final docs = await getApplicationDocumentsDirectory();
    final brandingDir = Directory(p.join(docs.path, 'branding'));
    if (!await brandingDir.exists()) {
      await brandingDir.create(recursive: true);
    }
    final destDocs = p.join(brandingDir.path, 'app_icon_source.png');
    await File(iconoPath).copy(destDocs);

    // Si estamos en modo desarrollo con el repo montado, actualizar assets
    final candidates = <String>[
      p.join(Directory.current.path, 'assets', 'branding'),
      '/workspace/assets/branding',
    ];
    for (final dirPath in candidates) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final destAsset = p.join(dirPath, 'app_icon.png');
        await File(iconoPath).copy(destAsset);
        await _intentarGenerarNativos(iconoPath);
        return destAsset;
      }
    }

    debugPrint(
      'Icono guardado en $destDocs. '
      'Para el instalador, copiá este archivo a assets/branding/app_icon.png '
      'y ejecutá: dart run flutter_launcher_icons',
    );
    return destDocs;
  }

  Future<void> _intentarGenerarNativos(String sourcePng) async {
    try {
      final script = File('/workspace/tool/apply_app_icon.py');
      if (!await script.exists()) return;
      final result = await Process.run(
        'python3',
        [script.path, sourcePng],
        workingDirectory: '/workspace',
      );
      debugPrint('apply_app_icon: ${result.stdout}\n${result.stderr}');
    } catch (e) {
      debugPrint('No se pudieron regenerar iconos nativos: $e');
    }
  }
}
