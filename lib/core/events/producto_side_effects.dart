import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/producto.dart';

/// Callbacks post-guardar de productos (plugins se registran aquí).
/// El core NO importa plugins; solo dispara estos hooks.
typedef ProductoSideEffect = Future<void> Function(
  Producto producto, {
  required String op,
});

class ProductoSideEffects {
  ProductoSideEffects._();

  static final List<ProductoSideEffect> _afterSave = [];

  static void registerAfterSave(ProductoSideEffect fn) {
    if (!_afterSave.contains(fn)) _afterSave.add(fn);
  }

  static Future<void> runAfterSave(
    Producto producto, {
    required String op,
  }) async {
    for (final fn in List<ProductoSideEffect>.from(_afterSave)) {
      try {
        await fn(producto, op: op);
      } catch (e, st) {
        debugPrint('ProductoSideEffects($op): $e\n$st');
      }
    }
  }

  /// No bloquea el guardado del producto.
  static void scheduleAfterSave(
    Producto producto, {
    required String op,
  }) {
    unawaited(runAfterSave(producto, op: op));
  }
}
