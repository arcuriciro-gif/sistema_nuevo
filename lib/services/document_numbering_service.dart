import 'package:shared_preferences/shared_preferences.dart';

/// Prefijos y próximos números configurables por tipo de documento.
class DocumentNumberingService {
  DocumentNumberingService._();
  static final DocumentNumberingService instance = DocumentNumberingService._();

  static const _defaults = {
    'factura_a': 'FA',
    'factura_b': 'FB',
    'factura_c': 'FC',
    'presupuesto': 'PR',
    'nota_entrega': 'NE',
    'comprobante_interno': 'CI',
    'remito': 'TK',
  };

  final Map<String, String> prefijos = Map.from(_defaults);
  /// Si > 0, fuerza el próximo número (útil al migrar).
  final Map<String, int> proximos = {};

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in _defaults.keys) {
      prefijos[tipo] =
          prefs.getString('docPrefix_$tipo') ?? _defaults[tipo]!;
      proximos[tipo] = prefs.getInt('docNext_$tipo') ?? 0;
    }
  }

  Future<void> guardar({
    required Map<String, String> prefijos,
    required Map<String, int> proximos,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in prefijos.entries) {
      final clean = e.value.trim().toUpperCase();
      final value = clean.isEmpty ? (_defaults[e.key] ?? 'DOC') : clean;
      await prefs.setString('docPrefix_${e.key}', value);
      this.prefijos[e.key] = value;
    }
    for (final e in proximos.entries) {
      await prefs.setInt('docNext_${e.key}', e.value);
      this.proximos[e.key] = e.value;
    }
  }

  String prefijo(String tipo) =>
      prefijos[tipo] ?? _defaults[tipo] ?? 'DOC';

  int proximoForzado(String tipo) => proximos[tipo] ?? 0;

  static String labelTipo(String tipo) {
    switch (tipo) {
      case 'factura_a':
        return 'Factura A';
      case 'factura_b':
        return 'Factura B';
      case 'factura_c':
        return 'Factura C';
      case 'presupuesto':
        return 'Presupuesto';
      case 'nota_entrega':
        return 'Nota de entrega';
      case 'comprobante_interno':
        return 'Comprobante interno';
      case 'remito':
        return 'Remito / Ticket';
      default:
        return tipo;
    }
  }

  static List<String> get tipos => _defaults.keys.toList();
}
