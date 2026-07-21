import 'dart:io';

import 'package:flutter/material.dart';

import '../core/utils/media_path.dart';

/// Abre la foto a pantalla completa con zoom (útil en Windows .exe).
Future<void> showFotoAmpliada(
  BuildContext context, {
  required String path,
  String titulo = 'Foto',
}) async {
  final p = path.trim();
  if (p.isEmpty) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget imagen;
      if (esUrlRemota(p)) {
        imagen = Image.network(
          p,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            size: 72,
            color: cs.onInverseSurface,
          ),
        );
      } else {
        try {
          final file = File(p);
          if (!file.existsSync()) {
            imagen = Icon(
              Icons.broken_image_outlined,
              size: 72,
              color: cs.onInverseSurface,
            );
          } else {
            imagen = Image.file(
              file,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            );
          }
        } catch (_) {
          imagen = Icon(
            Icons.broken_image_outlined,
            size: 72,
            color: cs.onInverseSurface,
          );
        }
      }

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(ctx).width,
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
                  ),
                  child: imagen,
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
