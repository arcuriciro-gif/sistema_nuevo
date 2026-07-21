import 'dart:convert';

/// Tipos de eventos de dominio (Capacidad 3).
/// Los documentos NO mueven stock/dinero; estos eventos sí.
class DomainEventType {
  static const mercaderiaEntregada = 'MERCADERIA_ENTREGADA';
  static const mercaderiaEntregaRevertida = 'MERCADERIA_ENTREGA_REVERTIDA';
  static const mercaderiaRecibida = 'MERCADERIA_RECIBIDA';
  static const mercaderiaRecepcionRevertida = 'MERCADERIA_RECEPCION_REVERTIDA';
  static const ajusteInventario = 'AJUSTE_INVENTARIO';
  static const ventaCargadaCc = 'VENTA_CARGADA_CC';
  static const ventaCcRevertida = 'VENTA_CC_REVERTIDA';
  static const pagoRegistrado = 'PAGO_REGISTRADO';
  static const pagoAnulado = 'PAGO_ANULADO';
  /// Capacidad 6: remitos cobrables en ledger de dinero.
  static const remitoCargadoCc = 'REMITO_CARGADO_CC';
  static const remitoCcRevertido = 'REMITO_CC_REVERTIDO';
  static const remitoCobrado = 'REMITO_COBRADO';
  static const remitoCobroRevertido = 'REMITO_COBRO_REVERTIDO';
}

class DomainEvent {
  DomainEvent({
    required this.eventId,
    required this.type,
    required this.payload,
    this.aggregateType,
    this.aggregateId,
    this.createdBy,
    this.deviceId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String eventId;
  final String type;
  final Map<String, dynamic> payload;
  final String? aggregateType;
  final String? aggregateId;
  final String? createdBy;
  final String? deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toRow() => {
        'event_id': eventId,
        'type': type,
        'aggregate_type': aggregateType,
        'aggregate_id': aggregateId,
        'payload': jsonEncode(payload),
        'created_at': createdAt.toIso8601String(),
        'created_by': createdBy,
        'device_id': deviceId,
      };
}

class InventoryLine {
  InventoryLine({
    required this.productoId,
    required this.cantidad,
    this.productoCodigo,
  });

  final int productoId;
  final int cantidad;
  final String? productoCodigo;

  Map<String, dynamic> toJson() => {
        'productoId': productoId,
        'cantidad': cantidad,
        if (productoCodigo != null) 'productoCodigo': productoCodigo,
      };

  static InventoryLine fromJson(Map<String, dynamic> m) => InventoryLine(
        productoId: (m['productoId'] as num).toInt(),
        cantidad: (m['cantidad'] as num).toInt(),
        productoCodigo: m['productoCodigo']?.toString(),
      );
}
