import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../core/config/device_identity.dart';
import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../database/database_helper.dart';
import '../models/remito.dart';
import '../models/remito_detalle.dart';
import 'auth_service.dart';
import 'cuenta_corriente_service.dart';

class RemitoService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<String> generarNumero() async {
    final db = await dbHelper.database;
    final tag = await DeviceIdentity.shortTag();
    final r = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero, 3, 5) AS INTEGER)) AS maxN "
      "FROM remitos WHERE numero LIKE 'R-%'",
    );
    final maxN = (r.first['maxN'] as num?)?.toInt() ?? 0;
    // Sufijo de dispositivo: evita choque PC↔celular con el mismo correlativo.
    return 'R-${(maxN + 1).toString().padLeft(5, '0')}-$tag';
  }

  Future<int> insertar(Remito remito, List<RemitoDetalle> items) async {
    DomainBootstrap.ensureInitialized();
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.crear,
      operacion: 'crear remito',
    );
    final db = await dbHelper.database;

    final remitoId = await db.transaction((txn) async {
      final id = await txn.insert(
        'remitos',
        {
          'numero': remito.numero,
          'clienteId': remito.clienteId != null
              ? int.tryParse(remito.clienteId!)
              : null,
          'fecha': remito.fecha.toIso8601String(),
          'total': remito.total,
          'descuento': remito.descuento,
          'estado': remito.estado,
          'estadoPago': Remito.estadoDesdeMontos(
            remito.total,
            remito.totalPagado,
          ),
          'totalPagado': remito.totalPagado,
          'saldoPendiente': (remito.total - remito.totalPagado)
              .clamp(0, remito.total)
              .toDouble(),
          'observaciones': remito.observaciones,
          'fechaCreacion': DateTime.now().toIso8601String(),
        },
      );

      for (final item in items) {
        final productoRows = await txn.query(
          'productos',
          columns: ['costo'],
          where: 'id = ?',
          whereArgs: [item.productoId],
          limit: 1,
        );
        final costoUnitario = item.costoUnitario > 0
            ? item.costoUnitario
            : (productoRows.isNotEmpty
                    ? (productoRows.first['costo'] as num?)?.toDouble()
                    : 0) ??
                0;
        final ganancia = item.subtotal - (costoUnitario * item.cantidad);

        await txn.insert('remito_items', {
          'remitoId': id,
          'productoId': item.productoId,
          'cantidad': item.cantidad,
          'precio': item.precioUnitario,
          'subtotal': item.subtotal,
          'costoUnitario': costoUnitario,
          'ganancia': ganancia,
        });
        // Capacidad 3: el documento NO mueve stock.
      }

      return id;
    });

    // Política: remito confirmado ⇒ evento MERCADERIA_ENTREGADA.
    final lines = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item.cantidad == 0) continue;
      lines.add(InventoryLine(
        productoId: item.productoId,
        cantidad: item.cantidad,
      ).toJson());
    }
    if (lines.isNotEmpty) {
      final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
      final tag = await DeviceIdentity.shortTag();
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'inv:entrega:remito:$remitoId',
          type: DomainEventType.mercaderiaEntregada,
          aggregateType: 'remito',
          aggregateId: '$remitoId',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'remito',
            'documentId': '$remitoId',
            'documentNumero': remito.numero,
            'motivo': 'Entrega por remito ${remito.numero}',
            'lines': lines,
          },
        ),
      );
    }

    await FirestoreSyncService.instance.subirRemito(remitoId);
    final clienteIdInt =
        remito.clienteId != null ? int.tryParse(remito.clienteId!) : null;
    if (clienteIdInt != null) {
      await CuentaCorrienteService().recalcularSaldoCliente(clienteIdInt);
      // Capacidad 6: remito cobrable → money ledger (además del stock).
      if (remito.total > 0.009) {
        final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
        await DomainEventBus.instance.publish(
          DomainEvent(
            eventId: 'money:remito_cc:$remitoId',
            type: DomainEventType.remitoCargadoCc,
            aggregateType: 'remito',
            aggregateId: '$remitoId',
            createdBy: user,
            payload: {
              'clienteId': clienteIdInt,
              'remitoId': remitoId,
              'total': remito.total,
              'motivo': 'Remito ${remito.numero} a cuenta',
            },
          ),
        );
        if (remito.totalPagado > 0.009) {
          await DomainEventBus.instance.publish(
            DomainEvent(
              eventId: 'money:remito_cobrado_inicial:$remitoId',
              type: DomainEventType.remitoCobrado,
              aggregateType: 'remito',
              aggregateId: '$remitoId',
              createdBy: user,
              payload: {
                'clienteId': clienteIdInt,
                'remitoId': remitoId,
                'total': remito.totalPagado,
                'motivo': 'Pago inicial remito ${remito.numero}',
              },
            ),
          );
        }
      }
    }
    DataRefreshHub.instance.notifyTodo();
    return remitoId;
  }

  Future<List<Map<String, dynamic>>> obtenerTodosConCliente() async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT
        r.id,
        r.numero,
        r.clienteId,
        r.fecha,
        r.total,
        r.descuento,
        r.estado,
        r.estadoPago,
        r.observaciones,
        r.fechaCreacion,
        c.nombre AS clienteNombre
      FROM remitos r
      LEFT JOIN clientes c ON c.id = r.clienteId
      ORDER BY datetime(r.fecha) DESC, datetime(r.fechaCreacion) DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> obtenerPorCliente(int clienteId) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT
        r.id,
        r.numero,
        r.clienteId,
        r.fecha,
        r.total,
        r.descuento,
        r.estado,
        r.estadoPago,
        r.observaciones,
        r.fechaCreacion,
        c.nombre AS clienteNombre
      FROM remitos r
      LEFT JOIN clientes c ON c.id = r.clienteId
      WHERE r.clienteId = ?
      ORDER BY datetime(r.fecha) DESC, datetime(r.fechaCreacion) DESC
    ''', [clienteId]);
  }

  Future<List<Map<String, dynamic>>> obtenerItems(int remitoId) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT ri.*, p.descripcion, p.codigo, p.marca
      FROM remito_items ri
      JOIN productos p ON p.id = ri.productoId
      WHERE ri.remitoId = ?
    ''', [remitoId]);
  }

  Future<void> actualizarEstadoPago(int id, String estadoPago) async {
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.editar,
      operacion: 'cambiar estado de pago remito',
    );
    DomainBootstrap.ensureInitialized();
    final db = await dbHelper.database;
    final rows = await db.query(
      'remitos',
      columns: [
        'clienteId',
        'total',
        'numero',
        'estadoPago',
        'estado',
        'totalPagado',
        'saldoPendiente',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final total = (rows.first['total'] as num?)?.toDouble() ?? 0;
    final anterior =
        (rows.first['estadoPago']?.toString() ?? 'pendiente').trim();
    final nuevo = estadoPago.trim().isEmpty ? 'pendiente' : estadoPago.trim();
    if (anterior == nuevo && nuevo != 'cobrado') return;

    // Solo atajos de estado: cobrado = pagar todo el saldo; pendiente = reset.
    // Para montos parciales usar CuentaCorrienteService.registrarPagoRemito.
    double totalPagado;
    double saldoPendiente;
    if (nuevo == 'cobrado') {
      totalPagado = total;
      saldoPendiente = 0;
    } else if (nuevo == 'pendiente') {
      totalPagado = 0;
      saldoPendiente = total;
    } else {
      // 'parcial' sin monto: no cambia cifras (usar diálogo de cobro).
      return;
    }

    await db.update(
      'remitos',
      {
        'estadoPago': nuevo,
        'totalPagado': totalPagado,
        'saldoPendiente': saldoPendiente,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final clienteId = rows.first['clienteId'] as int?;
    final numero = rows.first['numero']?.toString() ?? '$id';
    final anulado = rows.first['estado']?.toString() == 'anulado';
    final pagadoAntes = (rows.first['totalPagado'] as num?)?.toDouble() ?? 0;

    if (!anulado && clienteId != null && total > 0.009) {
      final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
      if (nuevo == 'cobrado' && anterior != 'cobrado') {
        final delta = (total - pagadoAntes).clamp(0, total).toDouble();
        if (delta > 0.009) {
          await DomainEventBus.instance.publish(
            DomainEvent(
              eventId: 'money:remito_cobrado:$id:${DateTime.now().millisecondsSinceEpoch}',
              type: DomainEventType.remitoCobrado,
              aggregateType: 'remito',
              aggregateId: '$id',
              createdBy: user,
              payload: {
                'clienteId': clienteId,
                'remitoId': id,
                'total': delta,
                'motivo': 'Remito $numero cobrado',
              },
            ),
          );
        }
      } else if (anterior == 'cobrado' && nuevo == 'pendiente') {
        await DomainEventBus.instance.publish(
          DomainEvent(
            eventId: 'money:remito_cobro_rev:$id',
            type: DomainEventType.remitoCobroRevertido,
            aggregateType: 'remito',
            aggregateId: '$id',
            createdBy: user,
            payload: {
              'clienteId': clienteId,
              'remitoId': id,
              'total': pagadoAntes > 0.009 ? pagadoAntes : total,
              'motivo': 'Cobro remito $numero revertido',
            },
          ),
        );
      }
    }

    if (clienteId != null) {
      await CuentaCorrienteService().recalcularSaldoCliente(clienteId);
    }
    await FirestoreSyncService.instance.subirRemito(id);
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> anular(int id) async {
    DomainBootstrap.ensureInitialized();
    AuthorizationService.instance.require(
      'remitos',
      AuthzAction.anular,
      operacion: 'anular remito',
    );
    final db = await dbHelper.database;

    String? numero;
    int? clienteId;
    double total = 0;
    double saldoPendiente = 0;
    final lines = <Map<String, dynamic>>[];

    await db.transaction((txn) async {
      final remitos = await txn.query(
        'remitos',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (remitos.isEmpty) {
        return;
      }

      final remito = remitos.first;
      if (remito['estado'] == 'anulado') {
        return;
      }
      numero = remito['numero']?.toString();
      clienteId = remito['clienteId'] as int?;
      total = (remito['total'] as num?)?.toDouble() ?? 0;
      final pagado = (remito['totalPagado'] as num?)?.toDouble() ?? 0;
      final saldoRaw = (remito['saldoPendiente'] as num?)?.toDouble();
      saldoPendiente = saldoRaw ??
          (total - pagado).clamp(0, total).toDouble();

      final items = await txn.query(
        'remito_items',
        where: 'remitoId = ?',
        whereArgs: [id],
      );

      for (final item in items) {
        final productoId = item['productoId'] as int;
        final cantidad = item['cantidad'] as int? ?? 0;
        if (cantidad == 0) continue;
        lines.add(InventoryLine(
          productoId: productoId,
          cantidad: cantidad,
        ).toJson());
      }

      await txn.update(
        'remitos',
        {'estado': 'anulado'},
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    if (lines.isNotEmpty) {
      final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
      final tag = await DeviceIdentity.shortTag();
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'inv:entrega_rev:remito:$id',
          type: DomainEventType.mercaderiaEntregaRevertida,
          aggregateType: 'remito',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'remito',
            'documentId': '$id',
            'documentNumero': numero,
            'motivo': 'Reverso entrega remito ${numero ?? id}',
            'lines': lines,
          },
        ),
      );
    }

    if (clienteId != null && saldoPendiente > 0.009) {
      final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:remito_cc_rev:$id',
          type: DomainEventType.remitoCcRevertido,
          aggregateType: 'remito',
          aggregateId: '$id',
          createdBy: user,
          payload: {
            'clienteId': clienteId,
            'remitoId': id,
            'total': saldoPendiente,
            'motivo': 'Remito ${numero ?? id} anulado (saldo pendiente)',
          },
        ),
      );
    }

    if (clienteId != null) {
      await CuentaCorrienteService().recalcularSaldoCliente(clienteId!);
    }
    await FirestoreSyncService.instance.subirRemito(id);
    DataRefreshHub.instance.notifyTodo();
  }

  /// Anula (si hace falta) y borra el remito de este equipo y de la nube.
  Future<void> eliminar(int id) async {
    AuthorizationService.instance.requireAdmin(operacion: 'eliminar remitos');
    final db = await dbHelper.database;
    final rows = await db.query(
      'remitos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final remito = rows.first;
    final numero = remito['numero']?.toString() ?? '';
    if (remito['estado'] != 'anulado') {
      await anular(id);
    }
    // Capacidad 7: encolar tombstone ANTES del hard-delete local.
    if (numero.isNotEmpty) {
      await FirestoreSyncService.instance
          .eliminarRemitoRemoto(numero, localId: id);
    }
    await db.delete('remito_items', where: 'remitoId = ?', whereArgs: [id]);
    await db.delete('remitos', where: 'id = ?', whereArgs: [id]);
    DataRefreshHub.instance.notifyTodo();
  }

  Future<int> cantidad() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery('SELECT COUNT(*) total FROM remitos');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> totalVentas() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT SUM(total) total FROM remitos WHERE estado != 'anulado'",
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> totalVentasPorPeriodo(DateTime desde, DateTime hasta) async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT SUM(total) total FROM remitos WHERE estado != 'anulado' AND fecha >= ? AND fecha <= ?",
      [desde.toIso8601String(), hasta.toIso8601String()],
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> ventasPorMes({int meses = 6}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT strftime('%Y-%m', fecha) AS mes, SUM(total) AS total
      FROM remitos
      WHERE estado != 'anulado'
      AND fecha >= date('now', '-$meses months')
      GROUP BY strftime('%Y-%m', fecha)
      ORDER BY mes ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> topProductos({int limite = 5}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT p.descripcion, SUM(ri.cantidad) AS totalVendido, SUM(ri.subtotal) AS totalMonto
      FROM remito_items ri
      JOIN productos p ON p.id = ri.productoId
      JOIN remitos r ON r.id = ri.remitoId
      WHERE r.estado != 'anulado'
      GROUP BY ri.productoId
      ORDER BY totalVendido DESC
      LIMIT ?
    ''', [limite]);
  }

  Future<List<Map<String, dynamic>>> topClientes({int limite = 5}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT c.nombre, COUNT(r.id) AS cantidadRemitos, SUM(r.total) AS totalCompras
      FROM remitos r
      JOIN clientes c ON c.id = r.clienteId
      WHERE r.estado != 'anulado'
      GROUP BY r.clienteId
      ORDER BY totalCompras DESC
      LIMIT ?
    ''', [limite]);
  }
}
