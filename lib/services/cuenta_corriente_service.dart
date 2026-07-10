import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../database/database_helper.dart';
import '../models/pago.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import 'branding_service.dart';

class ClienteDeudor {
  final int clienteId;
  final String nombre;
  final String telefono;
  final double saldoPendiente;
  final int ventasPendientes;
  final DateTime? ultimaCompra;

  ClienteDeudor({
    required this.clienteId,
    required this.nombre,
    required this.telefono,
    required this.saldoPendiente,
    required this.ventasPendientes,
    this.ultimaCompra,
  });
}

class ResumenCuentasCobrar {
  final double montoTotalPendiente;
  final int clientesConDeuda;
  final int ventasPendientes;
  final ClienteDeudor? mayorDeudor;
  final List<Venta> proximosVencimientos;
  final List<String> alertas;

  ResumenCuentasCobrar({
    required this.montoTotalPendiente,
    required this.clientesConDeuda,
    required this.ventasPendientes,
    this.mayorDeudor,
    required this.proximosVencimientos,
    required this.alertas,
  });
}

class CuentaCorrienteService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  static String estadoDesdeMontos(double total, double pagado) =>
      Venta.calcularEstadoPago(total, pagado);

  Future<int> crearVentaConPago({
    required Venta venta,
    required List<VentaItem> items,
    double montoAbonado = 0,
    String medioPago = 'efectivo',
    String observacionesPago = '',
  }) async {
    final db = await _db.database;
    final abonado = montoAbonado.clamp(0, venta.total).toDouble();
    final saldo = (venta.total - abonado).clamp(0, venta.total).toDouble();
    final estadoPago = estadoDesdeMontos(venta.total, abonado);
    final vencimiento = venta.fechaVencimiento ??
        venta.fecha.add(
          Duration(days: BrandingService.instance.diasVencimiento),
        );

    final ventaMap = venta.toMap()
      ..remove('id')
      ..['totalPagado'] = abonado
      ..['saldoPendiente'] = saldo
      ..['estadoPago'] = estadoPago
      ..['fechaVencimiento'] = vencimiento.toIso8601String();

    final ventaId = await db.transaction((txn) async {
      final id = await txn.insert('ventas', ventaMap);
      for (final item in items) {
        await txn.insert(
          'ventas_items',
          item.toMap()
            ..remove('id')
            ..['ventaId'] = id,
        );
      }
      if (abonado > 0.009) {
        await txn.insert('pagos', {
          'ventaId': id,
          'clienteId': venta.clienteId,
          'fecha': DateTime.now().toIso8601String(),
          'monto': abonado,
          'medioPago': medioPago,
          'observaciones': observacionesPago,
        });
      }
      return id;
    });

    if (venta.clienteId != null) {
      await recalcularSaldoCliente(venta.clienteId!);
    }
    DataRefreshHub.instance.notifyVentas();
    return ventaId;
  }

  Future<Pago> registrarPago({
    required int ventaId,
    required double monto,
    required String medioPago,
    String observaciones = '',
    DateTime? fecha,
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a 0');
    }
    final db = await _db.database;
    final ventaRows = await db.query(
      'ventas',
      where: 'id = ?',
      whereArgs: [ventaId],
    );
    if (ventaRows.isEmpty) {
      throw StateError('Venta no encontrada');
    }
    final venta = Venta.fromMap(ventaRows.first);
    if (venta.estado == 'anulada') {
      throw StateError('No se puede cobrar una venta anulada');
    }
    if (venta.saldoPendiente <= 0.009) {
      throw StateError('La venta ya está pagada');
    }

    final montoAplicado =
        monto > venta.saldoPendiente ? venta.saldoPendiente : monto;
    final pago = Pago(
      ventaId: ventaId,
      clienteId: venta.clienteId,
      fecha: fecha ?? DateTime.now(),
      monto: montoAplicado,
      medioPago: medioPago,
      observaciones: observaciones,
    );

    await db.transaction((txn) async {
      await txn.insert('pagos', pago.toMap()..remove('id'));
      final nuevoPagado = venta.totalPagado + montoAplicado;
      final nuevoSaldo =
          (venta.total - nuevoPagado).clamp(0, venta.total).toDouble();
      await txn.update(
        'ventas',
        {
          'totalPagado': nuevoPagado,
          'saldoPendiente': nuevoSaldo,
          'estadoPago': estadoDesdeMontos(venta.total, nuevoPagado),
        },
        where: 'id = ?',
        whereArgs: [ventaId],
      );
    });

    if (venta.clienteId != null) {
      await recalcularSaldoCliente(venta.clienteId!);
    }
    await FirestoreSyncService.instance.subirVenta(ventaId);
    DataRefreshHub.instance.notifyVentas();
    return pago;
  }

  Future<void> recalcularSaldoCliente(int clienteId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(saldoPendiente), 0) AS saldo
      FROM ventas
      WHERE clienteId = ?
        AND estado != 'anulada'
        AND saldoPendiente > 0
        AND tipo NOT IN ('presupuesto')
    ''', [clienteId]);
    final saldo = (rows.first['saldo'] as num?)?.toDouble() ?? 0;
    await db.update(
      'clientes',
      {'saldo': saldo},
      where: 'id = ?',
      whereArgs: [clienteId],
    );
  }

  Future<List<Venta>> ventasDeCliente(int clienteId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.nombre AS clienteNombre
      FROM ventas v
      LEFT JOIN clientes c ON c.id = v.clienteId
      WHERE v.clienteId = ?
        AND v.tipo NOT IN ('presupuesto')
      ORDER BY v.fecha DESC, v.id DESC
    ''', [clienteId]);
    return rows.map(Venta.fromMap).toList();
  }

  Future<List<Venta>> ventasConSaldo({int? clienteId}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.nombre AS clienteNombre
      FROM ventas v
      LEFT JOIN clientes c ON c.id = v.clienteId
      WHERE v.estado != 'anulada'
        AND v.saldoPendiente > 0.009
        AND v.tipo NOT IN ('presupuesto')
        ${clienteId != null ? 'AND v.clienteId = ?' : ''}
      ORDER BY v.fecha ASC, v.id ASC
    ''', clienteId != null ? [clienteId] : []);
    return rows.map(Venta.fromMap).toList();
  }

  Future<List<Pago>> pagosDeCliente(int clienteId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.*, v.numero AS ventaNumero, c.nombre AS clienteNombre
      FROM pagos p
      LEFT JOIN ventas v ON v.id = p.ventaId
      LEFT JOIN clientes c ON c.id = p.clienteId
      WHERE p.clienteId = ?
      ORDER BY p.fecha DESC, p.id DESC
    ''', [clienteId]);
    return rows.map(Pago.fromMap).toList();
  }

  Future<List<Pago>> pagosDeVenta(int ventaId) async {
    final db = await _db.database;
    final rows = await db.query(
      'pagos',
      where: 'ventaId = ?',
      whereArgs: [ventaId],
      orderBy: 'fecha DESC, id DESC',
    );
    return rows.map(Pago.fromMap).toList();
  }

  Future<List<Pago>> pagosPorPeriodo(DateTime desde, DateTime hasta) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.*, v.numero AS ventaNumero, c.nombre AS clienteNombre
      FROM pagos p
      LEFT JOIN ventas v ON v.id = p.ventaId
      LEFT JOIN clientes c ON c.id = p.clienteId
      WHERE p.fecha >= ? AND p.fecha <= ?
      ORDER BY p.fecha DESC, p.id DESC
    ''', [desde.toIso8601String(), hasta.toIso8601String()]);
    return rows.map(Pago.fromMap).toList();
  }

  Future<List<ClienteDeudor>> clientesDeudores() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        c.id AS clienteId,
        TRIM(c.nombre || ' ' || COALESCE(c.apellido, '')) AS nombre,
        COALESCE(c.telefono, '') AS telefono,
        COALESCE(SUM(v.saldoPendiente), 0) AS saldoPendiente,
        COUNT(v.id) AS ventasPendientes,
        MAX(v.fecha) AS ultimaCompra
      FROM clientes c
      INNER JOIN ventas v ON v.clienteId = c.id
      WHERE v.estado != 'anulada'
        AND v.saldoPendiente > 0.009
        AND v.tipo NOT IN ('presupuesto')
      GROUP BY c.id
      HAVING saldoPendiente > 0.009
      ORDER BY saldoPendiente DESC
    ''');
    return rows
        .map(
          (r) => ClienteDeudor(
            clienteId: r['clienteId'] as int,
            nombre: (r['nombre'] as String?)?.trim().isNotEmpty == true
                ? (r['nombre'] as String).trim()
                : 'Sin nombre',
            telefono: r['telefono']?.toString() ?? '',
            saldoPendiente: (r['saldoPendiente'] as num?)?.toDouble() ?? 0,
            ventasPendientes: (r['ventasPendientes'] as int?) ?? 0,
            ultimaCompra: DateTime.tryParse(r['ultimaCompra']?.toString() ?? ''),
          ),
        )
        .toList();
  }

  Future<ResumenCuentasCobrar> resumenDashboard() async {
    final deudores = await clientesDeudores();
    final ventas = await ventasConSaldo();
    final monto = ventas.fold<double>(0, (s, v) => s + v.saldoPendiente);
    final mayor = deudores.isEmpty ? null : deudores.first;
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    DateTime vencimientoDe(Venta v) {
      if (v.fechaVencimiento != null) {
        final f = v.fechaVencimiento!;
        return DateTime(f.year, f.month, f.day);
      }
      final base = DateTime(v.fecha.year, v.fecha.month, v.fecha.day);
      return base.add(
        Duration(days: BrandingService.instance.diasVencimiento),
      );
    }

    final vencenHoy = ventas.where((v) {
      final venc = vencimientoDe(v);
      return venc == hoy;
    }).toList();

    final proximos = [...ventas]
      ..sort((a, b) => vencimientoDe(a).compareTo(vencimientoDe(b)));
    final alertas = <String>[];
    for (final d in deudores.take(3)) {
      alertas.add('${d.nombre} debe \$${d.saldoPendiente.toStringAsFixed(2)}');
    }
    for (final d in deudores.where((e) => e.ventasPendientes >= 3).take(2)) {
      alertas.add(
        '${d.nombre} posee ${d.ventasPendientes} facturas pendientes',
      );
    }
    if (vencenHoy.isNotEmpty) {
      alertas.add(
        'Hoy vencen ${vencenHoy.length} cuenta${vencenHoy.length == 1 ? '' : 's'} corriente${vencenHoy.length == 1 ? '' : 's'}',
      );
    }
    final vencidas = ventas.where((v) => vencimientoDe(v).isBefore(hoy)).length;
    if (vencidas > 0) {
      alertas.add('$vencidas venta${vencidas == 1 ? '' : 's'} vencida${vencidas == 1 ? '' : 's'}');
    }

    return ResumenCuentasCobrar(
      montoTotalPendiente: monto,
      clientesConDeuda: deudores.length,
      ventasPendientes: ventas.length,
      mayorDeudor: mayor,
      proximosVencimientos: proximos.take(5).toList(),
      alertas: alertas,
    );
  }

  Future<double> totalCobradoPeriodo(DateTime desde, DateTime hasta) async {
    final pagos = await pagosPorPeriodo(desde, hasta);
    return pagos.fold<double>(0, (s, p) => s + p.monto);
  }

  Future<double> deudaTotal() async {
    final ventas = await ventasConSaldo();
    return ventas.fold<double>(0, (s, v) => s + v.saldoPendiente);
  }
}
