import 'package:shared_preferences/shared_preferences.dart';

/// Política de integridad de inventario (Capacidad 8).
class IntegrityPolicy {
  IntegrityPolicy._();
  static final IntegrityPolicy instance = IntegrityPolicy._();

  static const _keyPermitirNegativo = 'integrity_permitir_stock_negativo';

  bool _permitirStockNegativo = false;
  bool _loaded = false;

  bool get permitirStockNegativo => _permitirStockNegativo;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _permitirStockNegativo = prefs.getBool(_keyPermitirNegativo) ?? false;
    _loaded = true;
  }

  Future<void> setPermitirStockNegativo(bool value) async {
    _permitirStockNegativo = value;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPermitirNegativo, value);
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await cargar();
  }

  /// ¿Se puede aplicar un delta que deje stock en [stockAfter]?
  Future<bool> permiteStockResultante(int stockAfter) async {
    await ensureLoaded();
    if (stockAfter >= 0) return true;
    return _permitirStockNegativo;
  }
}
