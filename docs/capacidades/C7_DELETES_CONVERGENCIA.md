# Capacidad 7 — Deletes durables y convergencia multi-dispositivo

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI + campo |
| Rama | `cursor/capacidad-7-deletes-convergencia-e44b` |
| Depende de | Capacidad 6 + pagos parciales (#40) |
| Cierra | Auditoría C8 (deletes offline) + A6 (inferencia por ausencia) + stock ops en prefs |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| Encolar tombstone **antes** del hard-delete local | Hecho | `RemitoService` / `VentaService` / `ClienteService` / `ProveedorService` |
| Tombstone apply en peers (venta/compra/proveedor) | Hecho | `_aplicarVentasRemotas` / `_aplicarComprasRemotas` / `_aplicarProveedoresRemotos` |
| No borrar por “ausencia” del snapshot | Hecho | set-difference removido en clientes/remitos |
| `opId` en tombstone remoto | Hecho | `buildTombstonePayload` |
| Stock ops durables en outbox | Hecho | `SyncOutbox.enqueueStockOp` + ejecución en batch |
| Tests | Hecho | `test/capacidad7_deletes_convergencia_test.dart` |

## Checklist de certificación Capacidad 7

- [x] Outbox delete antes de borrar SQLite
- [x] Tombstones con `opId` / `deletedAt` / `tombstone`
- [x] Apply remoto borra local en venta/compra/proveedor/remito/cliente
- [x] Sin deletes por set-difference
- [ ] **CI** verde en esta rama
- [ ] **Campo:** borrar remito offline → al reconectar desaparece en el otro dispositivo
- [ ] **Campo:** borrar cliente/proveedor en PC → APK cerrado → al abrir converge
- [ ] **Campo:** kill mid-delete → no resurrección

## Limitaciones

1. Catch-up upload sigue limitando a 2000 docs (paginación = capacidad posterior / B6).
2. Producto `eliminarDefinitivo` hard-local sin tombstone remoto queda diferido (usar soft-delete sync).
3. Compra no tiene hard-delete de producto; anulación + tombstone apply cubre convergencia.

## Veredicto

Capacidad 7 **lista para merge de desarrollo** tras CI verde.

> **Update 2026-07-21:** Capacidad 7 mergeada (#41). Capacidad 8 en curso: `docs/capacidades/C8_RECONCILIACION_ALARMAS.md`.

