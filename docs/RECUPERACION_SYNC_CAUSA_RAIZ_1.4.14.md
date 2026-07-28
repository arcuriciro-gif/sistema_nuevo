# Recuperación Sync Engine — causa raíz (1.4.14)

## Síntomas

- Windows tiene remitos / productos.
- APK: faltan remitos; faltan productos (p. ej. sin stock).
- Sync deja de converger.

## Causa raíz (remitos)

**Archivo:** `lib/core/sync/firestore_sync_service.dart`  
**Método:** `_aplicarRemitosRemotos`  
**Regresión:** `PRAGMA foreign_keys = ON` (forense 1.4.10) + resolución de ítem.

Flujo roto:

1. PC sube remito a Firestore (sí incluye `productoCodigo`).
2. En Windows, al subir remito, los productos solo se **encolan** (no se suben en el mismo gesto).
3. APK recibe el remito **antes** de tener el producto local.
4. Código viejo: si no encuentra el código, **deja el `productoId` del PC** (autoincrement).
5. `INSERT remito_items` → **FOREIGN KEY fail**.
6. El `catch` abortaba **todo** el snapshot → **ningún remito** queda en SQLite APK.
7. Cuando después llegan los productos, el listener de remitos **no reenvía** docs viejos → remitos perdidos para siempre.

Mismo anti-patrón en `_aplicarVentasRemotas` / `_aplicarComprasRemotas`.

## Causa raíz (productos / catálogo)

**Archivo:** `firestore.rules` match `productos` (hardening 1.4.11)

`allow create` exigía `stock` ausente o `== 0`.  
Un `stock_ops` con `FieldValue.increment` sobre un SKU **aún no creado** en nube hacía **CREATE** con stock ≠ 0 → **permission-denied** → catálogo incompleto en APK (incluye muchos sin movimiento / sin stock).

## Clasificación

| Cambio | Tipo |
|--------|------|
| `foreign_keys=ON` | necesario (integridad) — pero expuso bug latente |
| Usar `productoId` peer en apply | **regresión / bug** |
| Rules create productos stock==0 | **rompe sync** → revertido parcialmente |

## Fix mínimo (esta rama)

1. Resolver ítems **solo por `productoCodigo` → id local**; nunca peer id.
2. Un remito malo no aborta el resto (try por documento).
3. Tras aplicar productos en APK, re-pull remitos recientes (completa líneas).
4. Rules: `productos` create vuelve a `canWriteOps` (sin exigir stock 0).

## Productos “sin stock” en UI

Si el KPI **Con stock** está activo (`productos_page.dart` `_soloConStock`), la lista oculta `stock==0`.  
Tocar **Productos** / **Ver todos** / KPI **Sin stock**. No es pérdida de sync si el contador Sin stock > 0.
