import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/shell_menu_catalog.dart';

/// Modo de menú (solo UI — no cambia sync ni permisos de rol).
enum UiModoMenu { basico, completo }

/// Preferencias de qué ítems mostrar en la barra lateral.
/// Por defecto TODOS visibles. Se puede dejar vacía (ninguno obligatorio).
class SidebarPreferenciasService extends ChangeNotifier {
  SidebarPreferenciasService._();
  static final SidebarPreferenciasService instance =
      SidebarPreferenciasService._();

  static const _keyHidden = 'sidebar_hidden_ids_v1';
  static const _keyModo = 'ui_modo_menu_v1';

  /// Menú básico: vender y ver productos (sync sigue completa en background).
  static const Set<String> idsModoBasico = {
    'dashboard|Inicio',
    'remitos|Venta Rápida',
    'productos|Productos',
    'remitos|Ventas / Facturas',
    'stock|Stock',
    'clientes|Clientes',
    'dashboard|Mi perfil',
    'configuracion|Configuración',
  };

  final Set<String> _hidden = {};
  UiModoMenu _modo = UiModoMenu.completo;
  bool _listo = false;

  bool get listo => _listo;
  Set<String> get ocultos => Set.unmodifiable(_hidden);
  UiModoMenu get modo => _modo;

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
    final modoRaw = prefs.getString(_keyModo);
    _modo = modoRaw == 'basico' ? UiModoMenu.basico : UiModoMenu.completo;
    _listo = true;
    notifyListeners();
  }

  Future<void> aplicarModo(UiModoMenu modo) async {
    _modo = modo;
    if (modo == UiModoMenu.completo) {
      _hidden.clear();
    } else {
      final todos = kShellMenuCatalog.map((e) => e.id).toSet();
      _hidden
        ..clear()
        ..addAll(todos.difference(idsModoBasico));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyModo,
      modo == UiModoMenu.basico ? 'basico' : 'completo',
    );
    await _persistir();
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
