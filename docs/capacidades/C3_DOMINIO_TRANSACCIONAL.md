# Capacidad 3 — Dominio transaccional (auditoría de entrega)

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI + replay en campo |
| Rama | `cursor/capacidad-3-dominio-transaccional-e44b` |
| Depende de | Capacidad 2 (lista para merge de desarrollo) |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| Documentos ≠ movimientos | Hecho | Remito/compra/ajuste ya no mutan `productos.stock` directo |
| Event Bus in-process | Hecho | `lib/core/domain/event_bus.dart` |
| Eventos de inventario | Hecho | `MERCADERIA_ENTREGADA` / `_REVERTIDA`, `MERCADERIA_RECIBIDA` / `_REVERTIDA`, `AJUSTE_INVENTARIO` |
| Inventory ledger append-only | Hecho | Tabla `inventory_ledger` + proyección a `productos.stock` |
| Idempotencia por `eventId` | Hecho | Skip si `domain_events.event_id` existe |
| Money / CC ledger | Hecho | `money_ledger` + `VENTA_CARGADA_CC` / `PAGO_REGISTRADO` / `VENTA_CC_REVERTIDA` |
| Anulación = nuevo evento | Hecho | Remito/compra/venta emiten reverso; no borran ledger |
| Reconstrucción | Hecho | `reconstruirStock` / `reconstruirSaldo` / `verificarProyeccion` |
| Schema forward-only | Hecho | SQLite **v27** |
| Tests | Hecho | `test/capacidad3_dominio_test.dart` |

## Política de emisión (MVP)

| Documento / acción | Evento |
|---|---|
| Remito `insertar` | `MERCADERIA_ENTREGADA` |
| Remito `anular` | `MERCADERIA_ENTREGA_REVERTIDA` |
| Compra `insertar` | `MERCADERIA_RECIBIDA` (+ costo de catálogo, no es inventario) |
| Compra `anular` | `MERCADERIA_RECEPCION_REVERTIDA` |
| `StockService.registrarMovimiento` | `AJUSTE_INVENTARIO` |
| Venta CC (`crearVentaConPago`) | `VENTA_CARGADA_CC` (total) + `PAGO_REGISTRADO` (abonado) |
| `registrarPago` | `PAGO_REGISTRADO` |
| Venta `anular` (saldo > 0) | `VENTA_CC_REVERTIDA` |

## Checklist de certificación Capacidad 3

- [x] Schema v27 forward-only (`domain_events`, `inventory_ledger`, `money_ledger`)
- [x] Remito/Compra/StockService no hacen `UPDATE productos SET stock` directo
- [x] Handlers de ledger únicos vía `DomainBootstrap`
- [x] Tests unitarios / ledger con sqflite_ffi
- [ ] **CI:** `flutter test` + builds Android/Windows verdes en esta rama
- [ ] **Campo:** remito → stock baja; anular → stock vuelve; otro dispositivo no doble-descuenta (idempotencia nube `opId`)
- [ ] **Campo:** venta CC + pagos → `reconstruirSaldo` ≈ deuda de ventas (sin remitos en ledger dinero aún)
- [ ] **Campo:** stock histórico pre-C3 + ledger C3: usar `stockInicial` al reconciliar, no asumir ledger completo desde cero

## Limitaciones conocidas

1. **Stock histórico pre-v27** no está en `inventory_ledger`; `verificarProyeccion` solo cuadra para productos cuyo stock nace/opera bajo C3 (o con `stockInicial` explícito).
2. **Remitos en CC:** `recalcularSaldoCliente` sigue sumando remitos pendientes; el money ledger **aún no** emite eventos por remito cobrable (solo ventas/pagos).
3. Política tenant “cuándo emitir entrega” (ADR verticales) = hardcode remito→entrega en este MVP; configurable = Capacidad posterior / Fase C7 roadmap.
4. Sync cloud de stock sigue vía `ajustarStockEnNube` desde el handler (opId = `eventId_productoId`); no hay proyección remota del ledger completo.
5. `StockService.registrarMovimiento` retorna `0` (ya no id de `movimientos_stock`); el kardex legado se escribe desde el ledger.

## Veredicto

Capacidad 3 **lista para merge de desarrollo** tras CI verde.  
No iniciar Capacidad 4 hasta este veredicto + checklist CI. Certificación plena de dominio exige las pruebas de campo arriba.

> **Update 2026-07-21:** Capacidad 3 mergeada (#33). Capacidad 4 en curso: `docs/capacidades/C4_AUTORIZACION_REAL.md`.
