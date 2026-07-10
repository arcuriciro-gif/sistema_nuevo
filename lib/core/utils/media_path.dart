import 'dart:io';

import 'package:flutter/material.dart';

bool esUrlRemota(String? path) {
  if (path == null || path.isEmpty) return false;
  final p = path.toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://');
}

ImageProvider? imageProviderDesdePath(String? path) {
  if (path == null || path.isEmpty) return null;
  if (esUrlRemota(path)) return NetworkImage(path);
  final file = File(path);
  if (file.existsSync()) return FileImage(file);
  return null;
}
