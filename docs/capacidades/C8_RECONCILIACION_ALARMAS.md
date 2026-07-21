# Capacidad 8 — Reconciliación + alarmas de divergencia

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI + campo |
| Rama | `cursor/capacidad-8-reconciliacion-alarmas-e44b` |
| Depende de | Capacidad 7 (mergeada #41) |
| Cierra | Roadmap Fase C · C8 (invariante + alarma + stock negativo configurable) |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| Invariante stock reconciliable | Hecho | `base(stock_before) + ΣΔ = productos.stock` |
| Alarma divergencia stock / CC | Hecho | `IntegrityReconcileService` + tablas v29 |
| Money ledger vs saldo (informativo) | Hecho | kind `money_ledger` (legado pre-C3/C6 posible) |
| Stock negativo configurable | Hecho | `IntegrityPolicy.permitirStockNegativo` (default off) |
| Enforcement en remitos / ledger | Hecho | `assertPuedeAplicar` pre-insert + en apply |
| Panel técnico | Hecho | botón “Escanear integridad” + listado alarmas |
| Schema | Hecho | SQLite **v29** (`integrity_alarms`, `integrity_scan_meta`) |
| Tests | Hecho | `test/capacidad8_reconciliacion_test.dart` |

## Checklist de certificación Capacidad 8

- [x] Schema v29 + `schemaVersion` alineado
- [x] Escaneo persiste alarmas
- [x] Política stock negativo bloquea remito
- [ ] **CI** verde
- [ ] **Campo:** Panel técnico → Escanear → 0 alarmas en tenant sano post-C6/C7
- [ ] **Campo:** intentar remitir más stock del disponible → rechazo claro

## Limitaciones

1. Productos **sin** filas en `inventory_ledger` no se validan por proyección (legado pre-C3).
2. Alarmas `money_ledger` pueden aparecer en clientes históricos pre-C6; no implica corrupción de `clientes.saldo` operativo.
3. Escaneo limitado a 2000 productos con ledger / 5000 clientes (paginación completa = posterior).

## Veredicto

Capacidad 8 **lista para merge de desarrollo** tras CI verde.
