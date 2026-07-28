# Recuperación Sync Engine — causa raíz forense (1.4.14 / P0)

## Hipótesis

Con `PRAGMA foreign_keys = ON`, el apply de remitos/ventas/compras usaba el
`productoId` SQLite de Windows cuando el SKU aún no existía en Android → FK fail
→ abort del apply → datos no llegan.

**Veredicto: CONFIRMADA** (tests `test/sync_p0_fk_forense_evidence_test.dart`).

## Evidencia reproducible

| # | Hallazgo | Evidencia |
|---|----------|-----------|
| 1 | `PRAGMA foreign_keys = 1` | `DatabaseHelper` onConfigure (1.4.10 `383763d`) |
| 2 | SQL + excepción | `SqliteException(787) FOREIGN KEY constraint failed` al insertar `remito_items.productoId=99` |
| 3 | Causing statement | `INSERT INTO remito_items (remitoId, productoId, ...) VALUES (1, 99, …)` |
| 4 | Batch abort | Con resolve legado: R1 aplica, R2 FK, **R3 nunca se procesa**; watermark no avanza |
| 5 | Punto de pérdida | `_aplicarRemitosRemotos` — resolución de línea (pre-1.4.14) |

### Stacktrace (capturado en test)

```
SqliteException(787): FOREIGN KEY constraint failed
Causing statement: INSERT INTO remito_items (...) VALUES (?, ?, ...)
parameters: remitoId, peerProductoId(99|55), ...
#0 responseToResultOrThrow (sqflite_common_ffi)
```

### Archivo / método / condición

- **Archivo:** `lib/core/sync/firestore_sync_service.dart`
- **Método:** `_aplicarRemitosRemotos` (mismo patrón ventas/compras)
- **Condición:** `productoCodigo` no existe local **y** se conservaba `item['productoId']` del peer
- **Tabla:** `remito_items` FK → `productos(id)`

## Flujo donde desaparece el remito

```
Windows SQLite  → existe
Outbox          → encola / sube
Firestore     → documento existe (con productoCodigo + productoId peer)
Pull Android    → snapshot recibido
SQLite Android  → INSERT header OK; INSERT ítem con peer id → FK 787
                  catch outer → abort snapshot → R siguientes NO
Repository/UI   → remitos faltantes / incompletos
```

Cuando el catálogo llega después, el listener de remitos **no reenvía** docs
sin cambio → quedan perdidos hasta re-pull (`_repararRemitosTrasCatalogo`).

## Productos sin stock

1. **Sync:** rules 1.4.11 `productos` create exigía `stock` ausente/`==0`.
   `stock_ops` increment sobre SKU ausente = CREATE stock≠0 → permission-denied
   → catálogo incompleto (incluye muchos sin movimiento).
2. **UI:** `productos_page.dart` `_soloConStock` oculta `stock==0` si KPI
   “Con stock” quedó activo (IndexedStack). No es pérdida de sync si el
   contador Sin stock > 0.

## Clasificación de cambios recientes

| Cambio | Tipo |
|--------|------|
| `foreign_keys=ON` (1.4.10) | necesario — expuso bug latente |
| peer `productoId` en apply | **regresión** |
| rules create stock==0 (1.4.11) | **rompe sync** → revertido |
| resolve solo por codigo | **fix mínimo** |
| SyncPathLogger hops | instrumentación forense (no arquitectura nueva) |

## Fix mínimo

1. Resolver líneas **solo** por `productoCodigo` → id local (nunca peer id).
2. Si falta SKU: omitir línea + log `skipped_missing_sku` (header queda).
3. Tras catálogo en móvil: re-pull remitos recientes.
4. Rules: `productos` create = `canWriteOps`.
5. Logs `SYNC_PATH` con eventId/entityId/opId/transactionId/deviceId.

## Deploy

```bash
firebase deploy --only firestore:rules
```

## Verificación de campo

Instalar APK+EXE de este PR → Actualizar ahora → comparar conteos:
productos, productos sin stock (KPI / Ver todos), remitos, ventas, compras,
clientes, proveedores. Filtrar logcat por `SYNC_PATH`.
