import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../database/database_helper.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import 'auth_service.dart';
import 'cuenta_corriente_service.dart';
import 'document_numbering_service.dart';

class VentaService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final CuentaCorrienteService _cc = CuentaCorrienteService();

  // ── Número correlativo ────────────────────────────────────────────────────
  Future<String> siguienteNumero(String tipo) async {
    final db = await _db.database;
    final numbering = DocumentNumberingService.instance;
    final prefix = numbering.prefijo(tipo);
    final forzado = numbering.proximoForzado(tipo);
    final rows = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero, ${prefix.length + 2}) AS INTEGER)) as max "
      "FROM ventas WHERE tipo = ? AND numero LIKE ?",
      [tipo, '$prefix-%'],
    );
    final maxDb = (rows.first['max'] as int?) ?? 0;
    final next = forzado > maxDb ? forzado : maxDb + 1;
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<int> crear(
    Venta venta,
    List<VentaItem> items, {
    double montoAbonado = 0,
    String medioPago = 'efectivo',
    String observacionesPago = '',
  }) async {
    final id = await _cc.crearVentaConPago(
      venta: venta,
      items: items,
      montoAbonado: montoAbonado,
      medioPago: medioPago,
      observacionesPago: observacionesPago,
    );
    await FirestoreSyncService.instance.subirVenta(id);
    DataRefreshHub.instance.notifyVentas();
    return id;
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
    AuthorizationService.instance.require(
      'ventas',
      AuthzAction.anular,
      operacion: 'anular venta',
    );
    final db = await _db.database;
    final venta = await obtenerPorId(id);
    if (venta == null) return;
    if (venta.estado == 'anulada') return;

    final saldoAntes = venta.saldoPendiente;
    await db.update(
      'ventas',
      {
        'estado': 'anulada',
        'saldoPendiente': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (venta.clienteId != null) {
      await _cc.recalcularSaldoCliente(venta.clienteId!);
      // Anulación = nuevo evento (no borrar historial del ledger).
      if (saldoAntes > 0.009) {
        DomainBootstrap.ensureInitialized();
        final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
        await DomainEventBus.instance.publish(
          DomainEvent(
            eventId: 'money:venta_cc_rev:$id',
            type: DomainEventType.ventaCcRevertida,
            aggregateType: 'venta',
            aggregateId: '$id',
            createdBy: user,
            payload: {
              'clienteId': venta.clienteId,
              'ventaId': id,
              'monto': saldoAntes,
              'motivo': 'Anulación venta ${venta.numero}',
            },
          ),
        );
      }
    }
    await FirestoreSyncService.instance.subirVenta(id);
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
    await FirestoreSyncService.instance.subirVenta(id);
    DataRefreshHub.instance.notifyVentas();
  }

  Future<void> actualizarAfip(
    int id, {
    required String estadoAfip,
    String cae = '',
    DateTime? caeVencimiento,
    int puntoVenta = 0,
  }) async {
    final db = await _db.database;
    await db.update(
      'ventas',
      {
        'estadoAfip': estadoAfip,
        'cae': cae,
        'caeVencimiento': caeVencimiento?.toIso8601String(),
        'puntoVenta': puntoVenta,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await FirestoreSyncService.instance.subirVenta(id);
  }

  Future<void> eliminar(int id) async {
    AuthorizationService.instance.require(
      'ventas',
      AuthzAction.eliminar,
      operacion: 'eliminar venta',
    );
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
    if (venta != null) {
      await FirestoreSyncService.instance.eliminarVentaRemota(venta);
    }
    DataRefreshHub.instance.notifyVentas();
  }
}
