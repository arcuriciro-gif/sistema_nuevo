import '../core/events/data_refresh_hub.dart';
import '../database/database_helper.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import 'cuenta_corriente_service.dart';

class VentaService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final CuentaCorrienteService _cc = CuentaCorrienteService();

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
      case 'presupuesto':
        return 'PR';
      case 'nota_entrega':
        return 'NE';
      default:
        return 'TK';
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<int> crear(
    Venta venta,
    List<VentaItem> items, {
    double montoAbonado = 0,
    String medioPago = 'efectivo',
    String observacionesPago = '',
  }) {
    return _cc.crearVentaConPago(
      venta: venta,
      items: items,
      montoAbonado: montoAbonado,
      medioPago: medioPago,
      observacionesPago: observacionesPago,
    );
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
    final venta = await obtenerPorId(id);
    await db.update(
      'ventas',
      {
        'estado': 'anulada',
        'saldoPendiente': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (venta?.clienteId != null) {
      await _cc.recalcularSaldoCliente(venta!.clienteId!);
    }
    DataRefreshHub.instance.notifyVentas();
  }

  Future<void> actualizarEstadoPago(int id, String estadoPago) async {
    final db = await _db.database;
    final venta = await obtenerPorId(id);
    if (venta == null) return;

    double totalPagado = venta.totalPagado;
    double saldo = venta.saldoPendiente;
    if (estadoPago == 'cobrado') {
      totalPagado = venta.total;
      saldo = 0;
    } else if (estadoPago == 'pendiente') {
      totalPagado = 0;
      saldo = venta.total;
    } else if (estadoPago == 'parcial' && totalPagado <= 0) {
      totalPagado = venta.total / 2;
      saldo = venta.total - totalPagado;
    }

    await db.update(
      'ventas',
      {
        'estadoPago': estadoPago,
        'totalPagado': totalPagado,
        'saldoPendiente': saldo,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (venta.clienteId != null) {
      await _cc.recalcularSaldoCliente(venta.clienteId!);
    }
    DataRefreshHub.instance.notifyVentas();
  }

  Future<void> eliminar(int id) async {
    final db = await _db.database;
    final venta = await obtenerPorId(id);
    await db.transaction((txn) async {
      await txn.delete('pagos', where: 'ventaId = ?', whereArgs: [id]);
      await txn
          .delete('ventas_items', where: 'ventaId = ?', whereArgs: [id]);
      await txn.delete('ventas', where: 'id = ?', whereArgs: [id]);
    });
    if (venta?.clienteId != null) {
      await _cc.recalcularSaldoCliente(venta!.clienteId!);
    }
    DataRefreshHub.instance.notifyVentas();
  }
}
