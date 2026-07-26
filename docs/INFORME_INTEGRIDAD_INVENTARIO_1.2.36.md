# Informe — Sprint P0: Integridad del Inventario y Reglas de Negocio

**Versión:** 1.2.37+42  
**Fecha:** 2026-07-26  
**Alcance:** Solo consistencia de negocio (sin UI / CRM / WhatsApp / diseño)

---

## 1. Problemas encontrados

| ID | Problema | Severidad |
|---|---|---|
| R1 | `VentaService.anular` revertía stock fuera de la TX comercial | Crítica |
| R1 | `VentaService.eliminar` hard-delete sin anular/reverso | Crítica |
| R1 | No existía restaurar venta; ciclos anular×2 rompían eventIds fijos | Alta |
| R2 | Compras: riesgo de doble suma / skip idempotente en 2ª edición | Crítica |
| R2 | No existía reabrir compra anulada vía ledger | Alta |
| R3 | Política Remito+Factura ambigua → doble descuento | Crítica |
| R4 | Alta/edición/import escribían `productos.stock` absoluto | Crítica |
| R4 | `SqliteProductoRepository.actualizar` pisaba stock con snapshots viejos (favorito/fotos) | Crítica |
| R5 | Importaciones podían sobrescribir proyección sin movimiento | Crítica |
| R6 | Catch-up con `.get()` completo; sync remoto overwrite de stock | Crítica |
| R6 | Soft-delete remoto mergeaba stock absoluto a Firestore | Alta |
| R7 | Stock tratado como metadata editable | Crítica |

**No reabiertos (ya cerrados en 1.2.35):** código único, stock negativo default OFF, límite CC, tombstones, CUIT, AFIP/CAE, password salt, ledger en create remito/factura.

---

## 2. Cambios realizados

### Política oficial (R3) — **Opción B**
- Remito / nota_entrega / comprobante_interno → entregan.
- Factura A/B/C / presupuesto → solo documentan.
- Fuente única: `InventoryDeliveryPolicy` ← `Venta.mueveStock`.

### R1 — Anulación / eliminación / restauración
- `anular`: TX atómica; reverso solo si **neto ledger del documento < 0**.
- EventIds de reverso con `$rev` (ciclos anular↔restaurar seguros).
- `eliminar`: anula primero.
- `restaurar`: reabre estado/CC; re-entrega vía ledger si aplica (nunca write absoluto).

### R2 — Compras
- Create/edit/anular con `applyInTxn`.
- Ediciones con eventIds `$rev`.
- `reabrir`: confirma + recepción ledger con eventId único.
- Anular usa neto ledger (> 0) + eventId `$rev`.

### R4/R5 — Stock solo vía movimientos
- Alta: stock 0 + ajuste ledger.
- Edición/import: delta → ajuste.
- `SqliteProductoRepository.actualizar` **elimina `stock` del map** (imposible clobber).
- Soft-delete Firestore usa `actualizarSinStock`.

### R6 — Sync
- Catch-up paginado.
- Productos existentes: jamás overwrite de stock local.
- Outbox pendiente → no pisar metadata.

### R7 — Arquitectura
```
Documento → Ledger append-only → productos.stock (proyección)
```
Única escritura normal: `stock = stock + delta` en `InventoryLedgerService`.

---

## 3. Reglas de negocio definidas

1. **Opción B:** factura no entrega; remito/nota sí.
2. **Stock es proyección**, no maestro editable.
3. **Toda modificación de stock = asiento de ledger.**
4. **Anular** genera reverso (historial append-only).
5. **Eliminar** exige anulación previa.
6. **Restaurar venta / reabrir compra** reaplican vía nuevos eventIds (no reusan el alta).
7. **Decisión de reverso** = neto del ledger del documento (no solo el flag de tipo).
8. **Sync de productos** = metadata; stock por `stock_ops`.
9. **Idempotencia** por `domain_events.event_id`.
10. **Stock negativo** prohibido por default.

---

## 4. Escenarios extremos probados

Suite: `test/matriz_integridad_inventario_test.dart` (≥30 casos) + adversarial + capacidades.

| Caso | Stock esp. | Ledger | CC | Resultado |
|---|---|---|---|---|
| Remito -2 | 8 | OK | — | OK |
| Factura B misma op. | sin cambio | sin entrega | OK | OK |
| Nota anular/eliminar | restaurado | reverso | 0 | OK |
| Nota anular→restaurar→anular | 10→7→10 | ciclos | 0↔300 | OK |
| Restaurar factura B | sin stock | — | restaurada | OK |
| Compra edit 5→2→3 | 3 | rev+rec | — | OK |
| Compra anular→reabrir→anular | 5↔9 | sin doble | — | OK |
| Alta/import/ajuste | ledger | OK | — | OK |
| toggleFavorito con snapshot viejo | no clobber | — | — | OK |
| Doble anular remito | 10 | 1 rev | — | OK |
| Backup restore | DB completa (incl. ledgers) | — | — | estructural OK |

Suite completa: **todos los tests verdes**.

---

## 5. Riesgos que permanecen

1. Bootstrap de producto **nuevo** desde Firestore: semilla remota una vez (sin ledger local previo).
2. Lab multi-dispositivo real (Windows↔Android) no automatizado en CI sin Firebase.
3. Catch-up Windows corto al inicio (anti-crash); convergencia vía pull suave.
4. Campo stock visible en formularios (UI no tocada): el **servicio** lo convierte en movimiento; UX puede confundir.
5. Backups pre-ledger: al restaurar, proyección puede no tener historial completo (reconcile post-restore).

---

## 6. Veredicto de producción

### **APTO PARA PRODUCCIÓN del núcleo inventario / cuenta corriente**

Condiciones operativas recomendadas:
1. Merge de este PR (1.2.37+42) tras smoke Windows + Android.
2. Backup previo al upgrade.
3. Correr `IntegrityReconcileService` post-upgrade en DBs con facturas legado.
4. Smoke: remito + factura B, compra edit/reabrir, anular/restaurar nota, import CSV con stock, sync bidireccional.

**Conclusión:** el motor Documento → Ledger → Stock quedó cerrado de forma integral para R1–R7, incluyendo restaurar/reabrir y eliminación de writes absolutos residuales en metadata/sync.
