import 'dart:convert';

import '../core/config/device_identity.dart';
import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/events/data_refresh_hub.dart';
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

  Future<int> registrarMovimiento(MovimientoStock movimiento) async {
    DomainBootstrap.ensureInitialized();
    final user = movimiento.usuario.isNotEmpty
        ? movimiento.usuario
        : (AuthService.instance.currentUser?.usuario ?? 'sistema');
    final tag = await DeviceIdentity.shortTag();
    final eventId =
        'inv:ajuste:${DateTime.now().toUtc().microsecondsSinceEpoch}:${movimiento.productoId}';

    await DomainEventBus.instance.publish(
      DomainEvent(
        eventId: eventId,
        type: DomainEventType.ajusteInventario,
        aggregateType: 'producto',
        aggregateId: '${movimiento.productoId}',
        createdBy: user,
        deviceId: tag,
        payload: {
          'tipo': movimiento.tipo,
          'motivo': movimiento.motivo,
          'documentType': 'ajuste',
          'documentId': eventId,
          'lines': [
            InventoryLine(
              productoId: movimiento.productoId,
              cantidad: movimiento.cantidad,
            ).toJson(),
          ],
        },
      ),
    );

    await AuthService.instance.registrarCambio(
      'AJUSTE_STOCK',
      'inventory_ledger',
      'Movimiento ${movimiento.tipo} de ${movimiento.cantidad} unidades (producto ${movimiento.productoId})',
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
