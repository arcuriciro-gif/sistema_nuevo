import 'dart:convert';

import '../core/config/device_identity.dart';
import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/domain/inventory_ledger_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../database/database_helper.dart';
import '../models/movimiento_stock.dart';
import '../models/producto.dart';
import 'auth_service.dart';

class StockService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> obtenerMovimientos({int? productoId}) async {
    final db = await dbHelper.database;
    return db.rawQuery(
      '''
      SELECT m.*, p.descripcion AS productoNombre, p.codigo AS productoCodigo, p.stock AS stockActual
      FROM movimientos_stock m
      JOIN productos p ON p.id = m.productoId
      ${productoId != null ? 'WHERE m.productoId = ?' : ''}
      ORDER BY datetime(m.fecha) DESC, m.id DESC
      ''',
      productoId != null ? [productoId] : [],
    );
  }

  /// Único camino público para ajustes manuales: siempre via ledger in-TX.
  Future<int> registrarMovimiento(MovimientoStock movimiento) async {
    AuthorizationService.instance.require(
      AuthModules.stock,
      AuthzAction.editar,
      operacion: 'ajustar stock',
    );
    DomainBootstrap.ensureInitialized();
    if (movimiento.cantidad == 0) {
      throw ArgumentError('La cantidad del movimiento no puede ser 0.');
    }
    final tipo = movimiento.tipo == 'salida' ? 'salida' : 'entrada';
    final user = movimiento.usuario.isNotEmpty
        ? movimiento.usuario
        : (AuthService.instance.currentUser?.usuario ?? 'sistema');
    final tag = await DeviceIdentity.shortTag();
    final eventId =
        'inv:ajuste:${DateTime.now().toUtc().microsecondsSinceEpoch}:${movimiento.productoId}';
    final sign = tipo == 'salida' ? -1 : 1;

    final event = DomainEvent(
      eventId: eventId,
      type: DomainEventType.ajusteInventario,
      aggregateType: 'producto',
      aggregateId: '${movimiento.productoId}',
      createdBy: user,
      deviceId: tag,
      payload: {
        'tipo': tipo,
        'motivo': movimiento.motivo,
        'documentType': 'ajuste',
        'documentId': eventId,
        'lines': [
          InventoryLine(
            productoId: movimiento.productoId,
            cantidad: movimiento.cantidad.abs(),
          ).toJson(),
        ],
      },
    );

    final db = await dbHelper.database;
    final applied = await db.transaction((txn) async {
      return InventoryLedgerService.instance.applyInTxn(
        txn,
        event,
        sign: sign,
        movimientoTipo: tipo,
      );
    });

    if (applied) {
      InventoryLedgerService.instance.enqueueCloudAfterApply(event, sign: sign);
      await DomainEventBus.instance.publish(event);
    }

    await AuthService.instance.registrarCambio(
      'AJUSTE_STOCK',
      'inventory_ledger',
      'Movimiento $tipo de ${movimiento.cantidad.abs()} unidades (producto ${movimiento.productoId})',
      valorNuevo: jsonEncode({'eventId': eventId}),
    );

    DataRefreshHub.instance.notifyStock();
    return 0;
  }

  Future<List<Producto>> obtenerProductosConStockBajo({int limite = 5}) async {
    final db = await dbHelper.database;
    final resultado = await db.rawQuery(
      '''
SELECT * FROM productos
WHERE (stock_minimo > 0 AND stock <= stock_minimo)
   OR (stock_minimo = 0 AND stock <= ?)
ORDER BY stock ASC, descripcion
''',
      [limite],
    );

    return resultado.map((e) => Producto.fromMap(e)).toList();
  }
}
