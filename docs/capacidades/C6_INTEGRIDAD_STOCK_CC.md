# Capacidad 6 — Integridad stock nube + remitos en CC

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI + campo |
| Rama | `cursor/capacidad-6-integridad-stock-cc-e44b` |
| Depende de | Capacidad 5 (mergeada #35) + fix usuarios/empresa (#37) |
| Cierra | Auditoría C6 (`stock_ops` no atómico) + limitación C3 #2 (remitos fuera del money ledger) |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| `stock_ops` claim+increment atómicos | Hecho | `FirestoreProductoRepository.ajustarStock` vía `runTransaction` |
| Fallback estable (Windows) | Hecho | create-condicional + `status=pending_apply` |
| Reconciliador claims incompletos | Hecho | `reconcilizarStockOpsPendientes` en flush de cola |
| Remito → money ledger | Hecho | `REMITO_CARGADO_CC` / `_REVERTIDO` / `REMITO_COBRADO` / `_COBRO_REVERTIDO` |
| Cobrar remito emite evento | Hecho | `RemitoService.actualizarEstadoPago` + `cobrarRemitoCompleto` |
| Anular remito revierte deuda pendiente | Hecho | `REMITO_CC_REVERTIDO` si no estaba cobrado |
| Tests | Hecho | `test/capacidad6_integridad_test.dart` |

## Checklist de certificación Capacidad 6

- [x] Transacción Firestore en `ajustarStock` (o fallback seguro)
- [x] Ops incompletas no se borran (quedan `pending_apply`)
- [x] Tipos de evento remito estables en `DomainEventType`
- [x] Handlers en `MoneyLedgerService`
- [ ] **CI** verde en esta rama
- [ ] **Campo:** dos dispositivos mismo remito/SKU → stock nube sin doble delta
- [ ] **Campo:** remito a cliente → saldo CC; cobrar → saldo baja; anular pendiente → saldo vuelve

## Limitaciones

1. Remitos **históricos** (pre-C6) no están backfilleados al money ledger; `reconstruirSaldo` solo cuadra para operaciones nuevas bajo C6 (+ ventas/pagos C3).
2. Índice Firestore compuesto no hace falta para `status == pending_apply` en colección `stock_ops` (query simple).
3. `recalcularSaldoCliente` sigue siendo la fuente operativa del campo `clientes.saldo` (suma documentos); el ledger es certificable en paralelo.

## Veredicto

Capacidad 6 **lista para merge de desarrollo** tras CI verde.
