import 'dart:io';

import 'package:flutter/material.dart';

import '../core/utils/media_path.dart';

/// Avatar de foto de producto/cliente: muestra la imagen real (local o https).
/// Si falla la carga, cae a la inicial (nunca un círculo vacío confuso).
class MediaAvatar extends StatelessWidget {
  final String? path;
  final double radius;
  final String fallbackLetter;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const MediaAvatar({
    super.key,
    required this.path,
    this.radius = 26,
    this.fallbackLetter = '?',
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.primaryContainer;
    final fg = foregroundColor ?? cs.onPrimaryContainer;
    final letter = fallbackLetter.isNotEmpty
        ? fallbackLetter.substring(0, 1).toUpperCase()
        : '?';
    final size = radius * 2;
    final p = path?.trim() ?? '';

    Widget fallback() => CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          child: Text(
            letter,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.7,
            ),
          ),
        );

    if (p.isEmpty) return fallback();

    if (esUrlRemota(p)) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            p,
            fit: BoxFit.cover,
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, error, stack) => fallback(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: size,
                height: size,
                color: bg,
                alignment: Alignment.center,
                child: SizedBox(
                  width: radius,
                  height: radius,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final file = File(p);
    if (!file.existsSync()) return fallback();

    return ClipOval(
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => fallback(),
      ),
    );
  }
}
