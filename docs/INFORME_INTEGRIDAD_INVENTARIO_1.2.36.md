# Informe — Sprint P0: Integridad del Inventario y Reglas de Negocio

**Versión:** 1.2.36+41  
**Fecha:** 2026-07-26  
**Alcance:** Solo consistencia de negocio (sin UI / CRM / WhatsApp / diseño)

---

## 1. Problemas encontrados

| ID | Problema | Severidad |
|---|---|---|
| R1 | `VentaService.anular` revertía stock vía event bus **fuera** de la TX comercial | Crítica |
| R1 | `VentaService.eliminar` hacía hard-delete **sin anular** ni revertir stock/CC | Crítica |
| R2 | Compras editaban con eventIds fijos → 2ª edición podía skip idempotente | Crítica |
| R2 | Recepción de compra podía quedar post-TX (parcialmente corregido antes; consolidado) | Alta |
| R3 | Política Remito+Factura ambigua → riesgo de doble descuento | Crítica |
| R4 | `ProductoService.insertar/actualizar` escribían `productos.stock` absoluto | Crítica |
| R5 | Import CSV/Excel (`insertarLista` + formulario) sobrescribía stock sin ledger | Crítica |
| R6 | `_pullInicialCatchUp` usaba `.get()` completo en ventas/remitos/compras/… | Alta |
| R6 | `_aplicarProductosRemotos` pisaba stock local con snapshot remoto absoluto | Crítica |
| R7 | Stock trataba de ser editable y sincronizable como metadata | Crítica |

**No reabiertos (ya cerrados en 1.2.35):** código único, stock negativo default OFF, límite CC, tombstones, CUIT, AFIP/CAE, password salt, ledger en create remito/factura.

---

## 2. Cambios realizados

### Política oficial (R3) — **Opción B**
- **Remito / nota_entrega / comprobante_interno** → entregan mercadería (mueven stock).
- **Factura A/B/C / presupuesto** → solo documentan (NO mueven stock).
- Fuente única: `lib/core/domain/inventory_delivery_policy.dart`
- `Venta.mueveStock` delega a esa política.

### R1 — Anulación / eliminación de ventas
- `anular`: estado + reverso inventario (si hubo entrega o legado) + money ledger **en la misma TX**.
- Detecta entrega legado `inv:entrega:venta:$id` aunque la factura actual ya no mueva stock.
- `eliminar`: **anula primero**, luego tombstone remoto + hard-delete local.

### R2 — Compras
- `insertar` / `anular` / `actualizar` aplican ledger con `applyInTxn` en la misma TX.
- Ediciones usan eventIds con `$rev` (microseconds) para evitar skip idempotente falso.
- Flujo: reverso líneas viejas → recepción líneas nuevas.

### R4/R5 — Stock solo vía movimientos
- Alta producto: inserta con stock `0` + ajuste ledger de inventario inicial.
- Edición: conserva stock actual; cualquier delta del formulario → `ajusteInventario`.
- `insertarLista` / importaciones: mismo patrón (metadata + movimientos).
- `StockService.registrarMovimiento`: `applyInTxn` dentro de TX SQLite.

### R6 — Sync
- Catch-up inicial **paginado** (sin `.get()` completo de colecciones grandes).
- Productos existentes: **nunca** se sobrescribe `stock` desde el doc remoto.
- Outbox pendiente del producto → no pisar metadata local.

### R7 — Arquitectura
```
Documento comercial
        ↓
Movimiento de Inventario (ledger append-only)
        ↓
Proyección productos.stock
```
Única escritura de proyección: `InventoryLedgerService.applyInTxn` (`stock = stock + delta`).

### Ledger hardening
- Rechaza producto inexistente.
- Agrega líneas duplicadas del mismo producto.
- Rechaza cantidades negativas.
- Verifica que el `UPDATE` afecte exactamente 1 fila.

---

## 3. Reglas de negocio definidas

1. **Una sola política de entrega (Opción B):** factura no entrega; remito/nota sí.
2. **Stock es proyección**, no dato maestro editable.
3. **Toda modificación de stock genera asiento de ledger** (entrega, recepción, ajuste, importación, alta).
4. **Anular documento de entrega** genera movimiento de reverso (no “deshacer” el historial).
5. **Eliminar documento** exige anulación previa (reverso antes de borrar).
6. **No existe “restaurar factura”** en el producto: la anulación es terminal; el historial queda auditable.
7. **Editar compra** = reverso + nueva recepción (nunca reaplicar el mismo eventId).
8. **Sync remoto de productos** sincroniza metadata; el stock converge por `stock_ops` / increments, no por overwrite absoluto.
9. **Idempotencia** por `domain_events.event_id` + `inventory_ledger.event_id`.
10. **Stock negativo** sigue prohibido por default (`IntegrityPolicy`).

---

## 4. Escenarios extremos probados

Suite: `test/matriz_integridad_inventario_test.dart` + adversarial actualizado.

| Caso | Stock esp. | Ledger | CC | Resultado |
|---|---|---|---|---|
| Remito -2 | 8 | +10-2 | — | OK |
| Factura B -2 (misma op.) | 8 (sin cambio) | sin entrega | OK | OK |
| Nota entrega -3 + anular | 10 | +10-3+3 | 0 | OK |
| Eliminar nota (anula primero) | 10 | reverso | 0 | OK |
| Anular factura B | 10 | sin inv | 0 | OK |
| Remito anular / eliminar | 10 | reverso | — | OK |
| Compra +3 | 8 (desde 5) | recepción | — | OK |
| Compra edit 5→2→3 | 3 | rev+rec×2 | — | OK |
| Compra anular | stock previo | reverso | — | OK |
| Alta stock 15 | 15 | ajuste | — | OK |
| Edit stock 10→13 | 13 | +3 | — | OK |
| Import lista stock 7 | 7 | ajuste | — | OK |
| Ajuste manual -2 | 8 | salida | — | OK |
| Doble anular remito | 10 | 1 rev | — | OK |
| Código vacío / dup / costo-precio neg | — | — | — | rechazado |
| Límite CC | stock intacto | — | bloquea | OK |

---

## 5. Riesgos que permanecen

1. **Bootstrap de producto nuevo desde Firestore:** al insertar por primera vez se acepta el stock remoto como semilla (no hay ledger local previo). Mitigado: no se vuelve a sobrescribir si ya existe local.
2. **No hay “restaurar” documentos anulados** (venta/compra/remito). Es decisión de integridad; recuperar implica nuevo documento.
3. **Multi-empresa / tenancy:** el motor queda listo (eventIds + ledgers por documento), pero el aislamiento multi-tenant completo no es parte de este sprint.
4. **Catch-up Windows** sigue siendo paginado corto al inicio (anti-crash); la convergencia completa depende del pull suave periódico.
5. **Reglas Firestore en producción** deben redesplegarse si hubo cambios de rules (no tocadas en este sprint de dominio).
6. **Pruebas de conflicto online/offline reales entre 2 dispositivos** requieren laboratorio con Firebase; la suite local cubre idempotencia y proyección SQLite.

---

## 6. Veredicto de producción

### Condicional: **APTO PARA PRODUCCIÓN del núcleo de inventario/CC** si se cumplen:

1. Tests verdes de este sprint (`matriz_integridad_inventario_test` + adversarial + capacidades).
2. Smoke en Windows + Android: crear remito, factura B, compra, anular, importar CSV con stock, sync bidireccional sin drift de stock.
3. Backup previo al deploy y corrida de `IntegrityReconcileService` post-upgrade en DBs existentes (facturas legado que sí movieron stock quedan cubiertas por detección de `inv:entrega:venta:$id` al anular).

### No apto aún como “ERP completo sin riesgos” si se exige:
- Laboratorio multi-dispositivo formal documentado, o
- UI que oculte el campo stock absoluto (hoy el campo puede existir; el **servicio** lo convierte en movimiento — correcto, pero UX puede confundir).

**Conclusión operativa:** el motor Documento → Ledger → Stock quedó cerrado de forma integral para R1–R7. El sistema puede considerarse **APTO PARA PRODUCCIÓN en el núcleo de inventario y cuenta corriente**, con los riesgos residuales de arriba controlados operativamente.
