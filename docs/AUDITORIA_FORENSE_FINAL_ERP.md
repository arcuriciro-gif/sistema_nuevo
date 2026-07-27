# AUDITORÍA FORENSE FINAL — Tata.Manager ERP

**Fecha:** 2026-07-27  
**Versión auditada:** 1.4.9+77 (+ fixes P0 en esta rama → 1.4.10+78)  
**Rama:** `cursor/auditoria-forense-final-e44b`  
**Método:** adversarial — intentar refutar garantías desde el código; no confiar en docs de certificación previos.

---

## 1. Resumen ejecutivo

El sistema **no** estaba certificado de forma defensable.

Se encontraron **múltiples contraejemplos reales** que refutaban G1–G6.  
Varios P0 se corrigieron en esta auditoría. Otros riesgos **permanecen**.

| Área | Veredicto |
|------|-----------|
| Stock / ledger local | Sólido en el happy-path; autoridad aún bypasseable |
| Sync / ACK stock_op | Mejorado; dependía de rules rotas |
| Convergencia multi-dispositivo | Eventual frágil; tombstone id mismatch abierto |
| Seguridad Firestore | P0 rules stock_ops **corregido**; otros HIGH abiertos |
| Crashes UI | Residual HIGH en venta/dashboard |
| Rendimiento | Catch-up unbounded + ledger sin retención |

**Veredicto final:** el módulo de stock pasa de “falsamente certificado” a **parcialmente endurecido**.  
**No** se declara certificación completa G1–G7.

---

## 2. Arquitectura encontrada

```
Comercial (venta/compra/remito)
  → DomainEvent + InventoryLedgerService.applyInTxn (SQLite TX)
      → domain_events + inventory_ledger + productos.stock+=δ
      → sync_outbox stock_op + stock_ops_applied
  → Outbox pump → Firestore stock_ops + FieldValue.increment
  → ACK solo si status=applied (cliente)
Peer pull → applyRemoteStockOp (enqueueOutbound=false)
Watermark at+docId + hold-set anti-HOL
```

Autoridad declarada: ledger local / stock_ops cloud.  
Autoridad real: también writes absolutos y rules client-side.

---

## 3. Hallazgos críticos (P0)

### P0-1 Absolute stock + stock_ops = doble conteo cloud
**Refutaba:** G1, G6  
**Evidencia:** `_subirProductosAusentesEnNube` usaba `incluirStockAbsoluto: true` mientras alta/import ya encolan increments.  
**Fix:** `incluirStockAbsoluto: false` en ese camino.

### P0-2 Rules: create `stock_ops` con `status=applied` sin increment
**Refutaba:** G1, G2, G3  
**Evidencia:** `firestore.rules` permitía create applied; cliente trata applied como proof → ACK / skip peer.  
**Fix:** create solo `pending_apply|claimed`; update exige `codigo`/`delta` inmutables.

### P0-3 `reverseDocumentLocally` encolaba cloud (default true)
**Refutaba:** G1, G6  
**Evidencia:** comentario decía “No encola cloud”; `applyInTxn` usaba default `enqueueOutboundStockOps: true`.  
**Fix:** `enqueueOutboundStockOps: false`.

### P0-4 Watermark avanzaba saltando ops malformed
**Refutaba:** G2  
**Evidencia:** `opId/codigo/delta` inválidos hacían `continue` sin hold.  
**Fix:** park `malformed` + contar como blocker; hold upsert no pisa delta con null.

### P0-5 C8 auto-seed laundering
**Refutaba:** G4, G5, G7  
**Evidencia:** `scanAndPersist` llamaba `LegacyLedgerMigration.seedMissing` y convertía proyección ilegal en ledger “válido”.  
**Fix:** seed **no** corre en cada scan; solo boot explícito / panel; alarma `legacy_without_ledger` permanece.

---

## 4. Hallazgos importantes (P1)

| ID | Hallazgo | Impacto |
|----|----------|---------|
| P1-1 | Tombstone reverse usa `documentId` local del peer; ledger guarda id de origen | Reverso no corre en peer → divergencia si faltan stock_ops de anulación |
| P1-2 | SQLite FK nunca estaban ON | Orphans posibles |
| P1-3 | `SqliteProductoRepository.insertar` acepta stock absoluto | Bypass de autoridad ledger |
| P1-4 | Catch-up Android `.get()` sin límite clientes/proveedores | RAM/CPU/lecturas |
| P1-5 | `inventory_ledger` / `stock_ops_applied` sin retención | Crecimiento ilimitado |
| P1-6 | FCM tokens legibles/borrables por cualquier member ops | Privacidad / DoS push |
| P1-7 | Tenant update sin constraint de campos (`ownerUid`, `allowSelfJoin`) | Hijack / self-join |
| P1-8 | Password bootstrap `admin123` | Admin local por defecto |
| P1-9 | Windows catch-up omite stock_ops | G6 diferida (soft-pull mitiga) |
| P1-10 | `venta_factura_page` / `dashboard_page` async sin `mounted` | Crash Navigator/setState |

**Fix P1-2 aplicado:** `PRAGMA foreign_keys = ON` en `onConfigure`.

---

## 5. Hallazgos menores (P2)

- Soft-pull interval “quiet 20s” definido pero no usado (siempre 60s).
- Prefs cola stock_ops sin cap (solo hechas cap 500).
- Falta índice `(document_type, document_id)` en `inventory_ledger`.
- Entity locks por opId, no por producto.
- `mayAckStockOp` no cableado al pump (G3 depende de throws).

---

## 6. Riesgos

1. Cliente malicioso / bug futuro aún puede escribir `productos.stock` absoluto en Firestore (catch-all rules).  
2. Peer tombstone sin stock_ops de reverse = stock fantasma.  
3. Poison payload corrupto tras force-requeue.  
4. Escala 500k productos / millones de ledger rows no certificada.  
5. Windows txn-less claim residual TOCTOU teórico.

---

## 7. Código afectado (fixes esta rama)

| Archivo | Cambio |
|---------|--------|
| `firestore.rules` | stock_ops create/update endurecido |
| `firestore_sync_service.dart` | no absolute seed; park malformed |
| `inventory_ledger_service.dart` | reverse sin enqueue |
| `stock_ops_pull_hold_store.dart` | no null-out delta |
| `integrity_reconcile_service.dart` | sin auto-seed en scan |
| `database_helper.dart` | foreign_keys ON |

---

## 8–9. Benchmark / recursos

No se midió CPU/RAM de campo en este entorno cloud.  
Observado en código:

| Métrica | Valor |
|---------|-------|
| Outbox pump | 25s Win / 40s móvil |
| Soft-pull | 60s |
| Stock_ops mobile | 45s |
| Shell badge | 12s |
| Catch-up clientes | unbounded `.get()` (P1-4) |
| Ledger | append-only, sin purge (P1-5) |

---

## 10. Cobertura de invariantes (post-fix P0)

| G | Antes (docs) | Tras auditoría adversarial | Estado |
|---|--------------|----------------------------|--------|
| G1 no doble apply | “Demostrada” | Absolute+ops, reverse enqueue, rules applied | **🟡 Parcial** (P0 fijados; absolute productos catch-all abierto) |
| G2 no pérdida | “Demostrada” | malformed skip, rules fake-applied | **🟡 Parcial** |
| G3 ACK⇒applied real | “Demostrada” | rules create applied | **🟡 Parcial** (rules fijadas; proof sigue siendo status only) |
| G4 reconstrucción | “Demostrada” | C8 laundering, insert stock | **🟡 Parcial** |
| G5 idempotencia retries | “Demostrada” | local UNIQUE OK | **✅ Demostrada** (local + opId cloud tras fixes) |
| G6 convergencia | “Demostrada” | absolute, reverse, tombstone ids | **❌ Refutada** hasta P1-1 |
| G7 proyección=ledger | “Demostrada” | empty=true, seed | **🟡 Parcial** |

---

## 11. Contraejemplos encontrados

1. Producto ausente en nube + stock local 10 + stock_op +10 → cloud 20.  
2. Create `stock_ops/{id}` `{status:applied, delta:-5}` → peers bajan stock / origen ACK sin increment.  
3. Tombstone reverse con `enqueueOutbound=true` → segunda familia de ops.  
4. Op `{opId:x, codigo:'', delta:1}` → watermark avanza, op perdida.  
5. C8 scan sobre proyección corrupta → seed “blanquea” historial.

---

## 12. Riesgos remanentes

- P1-1 tombstone documentId mismatch  
- Absolute `productos` writes vía rules catch-all  
- Repo SQLite insert con stock  
- Unbounded catch-up + ledger growth  
- Security FCM / tenant update / admin123  
- UI mounted gaps  

---

## 13. Recomendaciones priorizadas

1. **P0 deploy** rules nuevas + build 1.4.10 (esta rama).  
2. **P1-1** tombstone: resolver por `syncId`/remote document id en ledgerNet.  
3. **Rules productos:** prohibir write de `stock` desde cliente (solo Admin SDK / CF).  
4. **SqliteProductoRepository:** strip `stock` en insert salvo seed controlado.  
5. **Retención ledger** + paginar catch-up.  
6. **Rotar/disable admin123** por defecto.  
7. **Fix mounted** venta_factura + dashboard.  

---

## 14. Veredicto final

> Intentamos romper el sistema. Lo logramos en varios ejes.  
> Tras fixes P0, el núcleo ledger+outbox+ACK es **más sólido**, pero **G6 sigue refutada** (tombstone) y G1/G2/G3/G4/G7 quedan **parciales**.  
> **No** emitir certificado de producción completo hasta cerrar P1-1 y el write absoluto de `productos.stock` en rules.

Comités: Architect / Flutter / SQLite / Firestore / Distributed / QA / Security / Perf / ERP — consenso: **NO CERTIFICADO COMPLETO**.
