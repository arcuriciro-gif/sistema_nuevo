import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de qué ítems mostrar en la barra lateral.
/// Por defecto TODOS visibles. Se puede dejar vacía (ninguno obligatorio).
class SidebarPreferenciasService extends ChangeNotifier {
  SidebarPreferenciasService._();
  static final SidebarPreferenciasService instance =
      SidebarPreferenciasService._();

  static const _keyHidden = 'sidebar_hidden_ids_v1';

  final Set<String> _hidden = {};
  bool _listo = false;

  bool get listo => _listo;
  Set<String> get ocultos => Set.unmodifiable(_hidden);

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyHidden);
    _hidden.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).map((e) => '$e').toList();
        _hidden.addAll(list);
      } catch (_) {}
    }
    _listo = true;
    notifyListeners();
  }

  bool estaVisible(String itemId) => !_hidden.contains(itemId);

  Future<void> setVisible(String itemId, bool visible) async {
    if (visible) {
      _hidden.remove(itemId);
    } else {
      _hidden.add(itemId);
    }
    await _persistir();
    notifyListeners();
  }

  Future<void> setOcultos(Set<String> ids) async {
    _hidden
      ..clear()
      ..addAll(ids);
    await _persistir();
    notifyListeners();
  }

  Future<void> mostrarTodos() async {
    _hidden.clear();
    await _persistir();
    notifyListeners();
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHidden, jsonEncode(_hidden.toList()));
  }
}
