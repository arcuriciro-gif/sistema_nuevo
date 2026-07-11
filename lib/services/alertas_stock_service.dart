import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/producto.dart';
import 'auth_service.dart';
import 'comunicaciones_service.dart';

/// Genera notificaciones internas cuando hay stock bajo.
/// Sin FCM: usa SQLite + sync de notificaciones existente.
class AlertasStockService {
  AlertasStockService._();
  static final AlertasStockService instance = AlertasStockService._();

  static const _prefsDigestKey = 'alerta_stock_digest_dia';
  static const _prefsProductoPrefix = 'alerta_stock_prod_';

  bool _evaluando = false;

  String get _hoy {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<List<Producto>> _productosBajos({int limite = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.rawQuery(
      '''
SELECT * FROM productos
WHERE (deleted_at IS NULL OR deleted_at = '')
  AND (
    (stock_minimo > 0 AND stock <= stock_minimo)
    OR (stock_minimo = 0 AND stock <= ?)
  )
ORDER BY stock ASC, descripcion
''',
      [limite],
    );
    return resultado.map(Producto.fromMap).toList();
  }

  /// Evalúa stock bajo y notifica (digest diario + por producto).
  Future<int> evaluarYNotificar({bool forzarDigest = false}) async {
    if (_evaluando) return 0;
    _evaluando = true;
    try {
      final bajos = await _productosBajos();
      if (bajos.isEmpty) return 0;

      final destinos = await _destinos();
      if (destinos.isEmpty) return 0;

      final prefs = await SharedPreferences.getInstance();
      var creadas = 0;

      final digestDia = prefs.getString(_prefsDigestKey);
      if (forzarDigest || digestDia != _hoy) {
        final titulo = bajos.length == 1
            ? '1 producto con stock bajo'
            : '${bajos.length} productos con stock bajo';
        final cuerpo = bajos
            .take(5)
            .map((p) => '${p.descripcion} (stock ${p.stock})')
            .join(' · ');
        for (final usuario in destinos) {
          await ComunicacionesService.instance.crearNotificacion(
            usuarioDestino: usuario,
            tipo: 'stock',
            titulo: titulo,
            cuerpo: cuerpo,
            entidadTipo: 'stock',
            entidadId: 'alertas',
          );
          creadas++;
        }
        await prefs.setString(_prefsDigestKey, _hoy);
      }

      for (final p in bajos) {
        if (p.id == null) continue;
        final key = '$_prefsProductoPrefix${p.id}';
        final firma = '$_hoy:${p.stock}';
        if (prefs.getString(key) == firma) continue;
        for (final usuario in destinos) {
          await ComunicacionesService.instance.crearNotificacion(
            usuarioDestino: usuario,
            tipo: 'stock',
            titulo: 'Stock bajo: ${p.descripcion}',
            cuerpo: p.stockMinimo > 0
                ? 'Quedan ${p.stock} (mínimo ${p.stockMinimo})'
                : 'Quedan ${p.stock} unidades',
            entidadTipo: 'producto',
            entidadId: '${p.id}',
          );
          creadas++;
        }
        await prefs.setString(key, firma);
      }

      return creadas;
    } finally {
      _evaluando = false;
    }
  }

  /// Tras un movimiento: reevalúa si el producto quedó bajo.
  Future<void> evaluarProducto(int productoId) async {
    final bajos = await _productosBajos();
    final sigueBajo = bajos.any((e) => e.id == productoId);
    if (!sigueBajo) return;
    await evaluarYNotificar();
  }

  Future<List<String>> _destinos() async {
    final yo = AuthService.instance.currentUser?.usuario;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'usuarios',
      columns: ['usuario', 'rol'],
      where: 'activo = 1',
    );
    final set = <String>{};
    if (yo != null && yo.isNotEmpty) set.add(yo);
    for (final r in rows) {
      final rol = (r['rol'] ?? '').toString().toLowerCase();
      final u = (r['usuario'] ?? '').toString();
      if (u.isEmpty) continue;
      if (rol.contains('admin') || rol == 'administrador') {
        set.add(u);
      }
    }
    if (set.isEmpty && yo != null) set.add(yo);
    return set.toList();
  }
}
