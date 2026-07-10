import '../database/database_helper.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';

class VentaService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // ── Número correlativo ────────────────────────────────────────────────────
  Future<String> siguienteNumero(String tipo) async {
    final db = await _db.database;
    final prefix = _prefijoPorTipo(tipo);
    final rows = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero, ${prefix.length + 2}) AS INTEGER)) as max "
      "FROM ventas WHERE tipo = ? AND numero LIKE ?",
      [tipo, '$prefix-%'],
    );
    final max = (rows.first['max'] as int?) ?? 0;
    return '$prefix-${(max + 1).toString().padLeft(6, '0')}';
  }

  String _prefijoPorTipo(String tipo) {
    switch (tipo) {
      case 'factura_a':
        return 'FA';
      case 'factura_b':
        return 'FB';
      case 'factura_c':
        return 'FC';
      default:
        return 'TK';
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<int> crear(Venta venta, List<VentaItem> items) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final id = await txn.insert('ventas', venta.toMap()..remove('id'));
      for (final item in items) {
        await txn.insert(
          'ventas_items',
          item.toMap()
            ..remove('id')
            ..['ventaId'] = id,
        );
      }
      return id;
    });
  }

  Future<List<Venta>> obtenerTodas({String? tipo}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.nombre AS clienteNombre
      FROM ventas v
      LEFT JOIN clientes c ON c.id = v.clienteId
      ${tipo != null ? 'WHERE v.tipo = ?' : ''}
      ORDER BY v.fecha DESC, v.id DESC
    ''', tipo != null ? [tipo] : []);
    return rows.map(Venta.fromMap).toList();
  }

  Future<Venta?> obtenerPorId(int id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.nombre AS clienteNombre
      FROM ventas v
      LEFT JOIN clientes c ON c.id = v.clienteId
      WHERE v.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return Venta.fromMap(rows.first);
  }

  Future<List<VentaItem>> obtenerItems(int ventaId) async {
    final db = await _db.database;
    final rows = await db.query(
      'ventas_items',
      where: 'ventaId = ?',
      whereArgs: [ventaId],
    );
    return rows.map(VentaItem.fromMap).toList();
  }

  Future<void> anular(int id) async {
    final db = await _db.database;
    await db.update(
      'ventas',
      {'estado': 'anulada'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> actualizarEstadoPago(int id, String estadoPago) async {
    final db = await _db.database;
    await db.update(
      'ventas',
      {'estadoPago': estadoPago},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> eliminar(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn
          .delete('ventas_items', where: 'ventaId = ?', whereArgs: [id]);
      await txn.delete('ventas', where: 'id = ?', whereArgs: [id]);
    });
  }
}
