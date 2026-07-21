# Capacidad 9 — Catch-up sync paginado (sin techo oculto)

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI + campo |
| Rama | `cursor/capacidad-9-catchup-paginado-e44b` |
| Depende de | Capacidad 8 (mergeada #42) |
| Cierra | Roadmap B6 + limitación C2 #1 + auditoría A8 (parcial: catch-up) |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| Quitar techo fijo 2000 ventas/remitos/compras | Hecho | `SyncCatchup.enqueueDocumentCatchup` |
| Cursor persistente por entidad | Hecho | `sync_watermarks` key `catchup_cursor:*` |
| No reabrir ops ya `acked` | Hecho | `SyncOutbox.needsCatchupUpsert` |
| Drenar outbox en varios batches/ciclo | Hecho | `_procesarOutboxDrain` |
| Productos remotos sin techo 10k en “ausentes” | Hecho | paginación por `documentId` |
| Tests | Hecho | `test/capacidad9_catchup_test.dart` |

## Cómo funciona

Cada ciclo de sync:
1. Avanza el cursor `id ASC` de ventas / remitos / compras (páginas de 250, hasta 8 páginas ≈ 2000 ids/ciclo).
2. Solo encola upsert si el outbox **no tiene** la op o está `dead`.
3. Al terminar la tabla, el cursor vuelve a 0 (pasada completa a lo largo de varios ciclos).
4. Drena hasta 25 batches del outbox.

Así documentos viejos (id bajos) ya no quedan fuera para siempre.

## Checklist

- [x] Sin `limit: 2000` DESC hard-cut en catch-up
- [x] Cursor durable
- [x] Tests de cursor + needsCatchup
- [ ] **CI** verde
- [ ] **Campo:** tenant con >2000 remitos → los viejos terminan en la nube tras N ciclos

## Limitaciones

1. Watch de productos sigue con `limit: 10000` (listener Firestore); pull de ausentes ya pagina.
2. Clientes/proveedores ausentes siguen con `.get()` completo (aceptable a escala media).
3. Capacidad 8 (reconciliación) es PR separado (#42).

## Veredicto

Capacidad 9 **lista para merge de desarrollo** tras CI verde.
